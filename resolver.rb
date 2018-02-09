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
      dict[:playbook].find {|pb| pb[:name] == name } or
        raise "Playbook '#{playbook[:fqn]}' includes a playbook we don't have: #{name}"
    }
  end

  def find_role(dict, rolename)
    dict[:role].find {|r| r[:name] == rolename } or
      raise "Failed to find role: #{rolename}"
  end

  def find_on_role(dict, role, type, name)
    role = if !role.is_a?(Hash) then find_role(dict, role) else role end
    role[type].find {|t| t[:name] == name } or
      raise "Failed to find #{type}: #{role[:name]}::#{name}"
  end

  def find_task(dict, role, name)
    name = name.sub(/\.yml$/, '')
    if name =~ %r!^(?:roles/|\.\./\.\./(?:\.\./roles/)?)([^/]+)/tasks/([^/]+)$!
      role = find_role(dict, $1)
      name = $2
    end
    find_on_role(dict, role, :task, name)
  end

  def find_template(dict, role, name)
    if name =~ %r!^(?:roles/|\.\./\.\./(?:\.\./roles/)?)([^/]+)/templates/(.+)$!
      role = find_role(dict, $1)
      name = $2
    end
    find_on_role(dict, role, :template, name)
  end

  # dict[:role] is Array of role Hashes
  # keys: name, type, ...
  def resolve_role_deps(dict, role)
    role[:role_deps] = role[:role_deps].map {|depname|
      if depname =~ /\{\{.*\}\}/
        $stderr.puts "WARNING: skipping dynamic dependency of #{role[:name]} " +
                     "role on:\n" +
                     depname + "\n" +
                     "since expressions are not supported yet."
        next "dynamic dependency of #{role[:name]}"
      end

      begin
        find_role(dict, depname)
      rescue
        raise "Problem resolving deps for role #{role[:fqn]}: #{depname or 'nil'}"
      end
    }
  end

  # dict[:task] is Array of task Hashes; task is same Hash
  # keys: name, type, fqn, data, parent, args, ...
  def resolve_task_includes(dict, task)
    task[:included_tasks].map! {|name, args|
      incl_task = find_task(dict, task[:parent], name)
      if incl_task == nil
        raise "Task #{task[:fqn]} failed to find included task: #{name}.yml"
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
        puts "Problem resolving task '#{task[:fqn]}' include_vars: '#{name}'"
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
    task[:used_templates].map! {|file|
      if file =~ %r!\{\{.*\}\}!
        thing(task[:parent], :template,
              "dynamic template src in " + task[:fqn],
              task[:path],
              {:src => file, :data => {}})
      else
        find_template(dict, task[:parent], file)
      end
    }
#    pp (task[:used_templates].map {|tm| tm[:fqn] }) if task[:used_templates].length > 0
  end
end
