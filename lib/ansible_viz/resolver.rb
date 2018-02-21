#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'ostruct'
require 'pp'


class Resolver
  # Converts includes from names/paths to things.
  # Ensure you've loaded the whole bag before trying to resolve it.

  def process(dict)
    dict[:playbook].each {|playbook|
      resolve_playbook_includes(dict, playbook)
    }
    dict[:role].each {|role|
      resolve_role_deps(dict, role)
    }
    dict[:task].each {|task|
      resolve_task_includes(dict, task)
      resolve_task_include_vars(dict, task)
    }
    dict[:task].each {|task|
      task[:included_by_tasks].uniq!
      resolve_args(dict, task)
      resolve_templates(dict, task)
    }
  end

  def resolve_playbook_includes(dict, playbook)
    playbook[:include].map! {|name|
      name.sub!(/.yml$/, '')
      included_playbook = dict[:playbook].find {|pb| pb[:name] == name }
      unless included_playbook
        debug 1, "WARNING: Couldn't find playbook '#{name}' " \
                 "(included by playbook '#{playbook[:fqn]}')"
        included_playbook = thing(dict, :playbook, name,
                                  "unknown", unresolved: true,
                                  include: [])
      end
      included_playbook
    }
  end

  def find_role_by_name(dict, rolename)
    dict[:role].find {|r| r[:name] == rolename }
  end

  # Finds something of the given type and name within the given role.
  # The role can be a Hash or the name of a role.
  def find_on_role(dict, role, type, name)
    if !role.is_a?(Hash)
      # Role name supplied; find the corresponding role Hash.
      role_name = role
      role = find_role_by_name(dict, role_name)
      unless role
        raise "find_on_role called to find #{type} named '#{name}' on " \
              "non-existent role '#{role_name}'"
      end
    end
    debug 4, "      Find #{type} '#{name}' in role '#{role[:name]}'"
    role[type].find {|t| t[:name] == name }
  end

  def mk_unresolved_role(dict, role_name, path="unknown")
    thing(dict, :role, role_name, path,
          unresolved: true, role_deps: [],
          task: [], varfile: [], vardefaults: [], template: [])
  end

  # Returns [task, task_name, role].  role will be auto-vivified if
  # unresolvable, but task returned may be nil, to allow the caller to
  # report the context in which the task failed to resolve.
  def find_task(dict, role, name)
    debug 4, "   find_task(#{role[:name]}, #{name})"
    task_name = name.sub(/\.yml$/, '')
    if task_name =~ %r!^(?:roles/|\.\./\.\./(?:\.\./roles/)?)([^/]+)/tasks/([^/]+)$!
      role_name, task_name = $1, $2
      debug 4, "      finding role '#{role_name}' elsewhere in '#{task_name}'"
      role = find_role_by_name(dict, role_name)
      unless role
        debug 1, "WARNING: Couldn't find containing role '#{role_name}' " \
                 "while looking for task '#{name}'"
        role = mk_unresolved_role(dict, role_name)
      end
    end

    task = find_on_role(dict, role, :task, task_name)
    [task, task_name, role]
  end

  def find_template(dict, role, name)
    debug 4, "   find_template('#{role[:name]}', '#{name}')"
    if name =~ %r!^(?:roles/|\.\./\.\./(?:\.\./roles/)?)([^/]+)/templates/(.+)$!
      role_name, template_name = $1, $2
      debug 4, "      Finding template '#{template_name}' " +
               "elsewhere in '#{role_name}'"
      role = find_role_by_name(dict, role_name)
      name = template_name
    end
    find_on_role(dict, role, :template, name)
  end

  # dict[:role] is Array of role Hashes
  # keys: name, type, ...
  def resolve_role_deps(dict, role)
    role[:role_deps] = role[:role_deps].map {|depname|
      if depname =~ /\{\{.*\}\}/
        debug 4, "WARNING: skipping dynamic dependency of #{role[:name]} " +
                 "role on:\n" +
                 depname + "\n" +
                 "since expressions are not supported yet."
        next "dynamic dependency of #{role[:name]}"
      end

      dep = find_role_by_name(dict, depname)
      unless dep
        debug 1, "WARNING: Couldn't find role '#{depname or 'nil'}' " \
                 "(dependency of role '#{role[:fqn]}')"
        dep = mk_unresolved_role(dict, depname)
      end
      dep
    }
    if role[:role_deps].any?(&:nil?)
      raise "nil role dep for #{role[:fqn]}"
    end
  end

  # dict[:task] is Array of task Hashes; task is same Hash
  # keys: name, type, fqn, data, parent, args, ...
  def resolve_task_includes(dict, task)
    task[:included_tasks].map! {|name, args|
      debug 4, "Finding task '#{name}' included in task '#{task[:fqn]}'"
      incl_task, incl_task_name, role = find_task(dict, task[:parent], name)
      if incl_task.nil?
        debug 1, "WARNING: Couldn't find task '#{name}' "\
                 "(included by task '#{task[:fqn]}')"
        incl_task = thing(role, :task, incl_task_name, "unknown",
                          unresolved: true, args: [],
                          included_by_tasks: [], scope: [], var: [],
                          included_varfiles: [], included_tasks: [],
                          used_templates: [],
                          data: { registers: [] })
        incl_task
      end

      incl_task[:args] += args
      incl_task[:included_by_tasks].push task
      incl_task
    }
  end

  def resolve_task_include_vars(dict, task)
    task[:included_varfiles].map! {|name|
      begin
        if name =~ %r!\{\{.+\}\}!
          thing(task, :varfile,
                "dynamic include_vars in " + task[:fqn],
                task[:path],
                {:include => name, :var => []})
        elsif name =~ %r!^([^/]+).yml! or name =~ %r!^\.\./vars/([^/]+).yml!
          find_on_role(dict, task[:parent], :varfile, $1)
        elsif name =~ %r!^\.\./defaults/([^/]+).yml!
          find_on_role(dict, task[:parent], :vardefaults, $1)
        elsif name =~ %r!^\.\./\.\./([^/]+)/vars/([^/]+).yml!
          find_on_role(dict, $1, :varfile, $2)
        elsif name =~ %r!^(?:\.\./\.\./|roles/)([^/]+)/defaults/([^/]+).yml!
          find_on_role(dict, $1, :vardefaults, $2)
        else
          raise "Unhandled include_vars: #{name}"
        end
      rescue Exception
        debug 0, "Problem resolving task '#{task[:fqn]}' include_vars: '#{name}'"
        raise
      end
    }
    if task[:included_varfiles].include?(nil)
      raise "Task #{task[:fqn]} has nil varfiles"
    end
  end

  def resolve_args(dict, task)
    task[:args] = task[:args].uniq.map {|arg|
      thing(task, :var, arg, task[:path], {:defined => true})
    }
  end

  def resolve_templates(dict, task)
    task[:used_templates].map! {|template|
      debug 4, "Finding template '#{template}' used in #{task[:fqn]}"
      if template =~ %r!\{\{.*\}\}!
        thing(task[:parent], :template,
              "dynamic template src in " + task[:fqn],
              task[:path], src: template, data: {})
      else
        find_template(dict, task[:parent], template) or
          begin
            debug 1, "WARNING: Couldn't find template '#{template}' " \
                     "(included by task '#{task[:fqn]}')"
            thing(task[:parent], :template, template,
                  "unknown", unresolved: true,
                  src: template, data: {})
          end
      end
    }
    if task[:used_templates].length > 0
      templates = task[:used_templates].map {|tm| tm[:fqn] }
      debug 4, "   used_templates: " + templates.join(" ")
    end
  end
end
