#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require 'ostruct'
require 'pp'


class Postprocessor
  # Most 'business logic' should live here, IE calculating fancy stuff.
  # Must ensure everything grapher expects is set, even if to empty []/{}.

  def process(dict)
    dict[:role].each {|role| do_role(dict, role) }
    dict[:playbook].each {|playbook| do_playbook(dict, playbook) }
    dict[:role].each {|role|
      role[:task].each {|task|
        resolve_task_includes(dict, task)
      }
    }
  end

  def do_role(dict, role)
    role[:role_deps] = role[:role_deps].map {|depname|
      dep = dict[:role].find {|d| d[:name] == depname }
      if dep == nil
        raise "Role '#{role[:name]}' failed to find dependency: #{depname}"
      end
      dep
    }

    role[:task] ||= []
    role[:task].each {|task| do_task(dict, task) }
    role[:main_task] = role[:task].find {|task| task[:name] == 'main' }

    role[:varset] ||= []
    role[:varset].each {|varset| do_vars(role, varset) }
    if role[:vardefaults] != nil
      # Consider defaults/main.yml just another source of var definitions
      # Note the type is still :vardefaults
      vardefaults = role[:vardefaults][0]  # there can be only one
      vardefaults[:name] = 'defaults'
      do_vars(role, vardefaults)
      role[:varset].push vardefaults
      role.delete :vardefaults
    end
  end

  def do_vars(dict, varset)
    data = varset[:data]
    varset[:var] = data.keys.map {|varname|
      thing(varset, :var, varname, {:defined => true})
    }
  end

  def do_playbook(dict, playbook)
    data = playbook[:data][0]
    playbook[:role] = (data['roles'] || []).map {|role|
      if role.instance_of? Hash
        role = role['role']
      end
      dict[:role].find {|r| r[:name] == role }
    }.uniq  # FIXME

    playbook[:task] = (data['tasks'] || []).map {|task_h|
      path = task_h['include'].split(" ")[0]
      if path !~ %r!roles/([^/]+)/tasks/([^/]+)\.yml!
        raise "Bad include from playbook #{playbook[:name]}: #{path}"
      end
      role, task = $1, $2
      role = dict[:role].find {|r| r[:name] == role }
      role[:task].find {|t| t[:name] == task }
    }.compact.uniq  # FIXME
  end

  def do_task(dict, task)
    data = task[:data]
    role = task[:parent]

    task[:included_tasks] = data.find_all {|i|
      i.is_a? Hash and i['include']
    }.map {|i| i['include'].split(" ")[0].sub(/\.yml$/, '')
    }

    task[:included_varsets] = data.find_all {|i|
      i.is_a? Hash and i['include_vars']
    }.map {|i| i['include_vars'].split(" ")[0].sub(/\.yml$/, '')
    }.map {|n| role[:varset].find {|t| t[:name] == n } }

    # A fact is created by set_fact in a task. A fact defines a var for every
    # task which includes this task. Facts defined by the main task of a role
    # are defined for all tasks which include this role.
    task[:var] = data.map {|i|
      i['set_fact']
    }.compact.flat_map {|i|
      if i.is_a? Hash
        i.keys
      else
        [i.split("=")[0]]
      end
    }.map {|n|
      thing(task, :var, n, {:defined => true})
    }
  end

  def resolve_task_includes(dict, task)
    task[:included_tasks] = task[:included_tasks].map {|name|
      role = task[:parent]
      if name =~ %r!../../([^/]+)/tasks/([^/]+)!
        role = dict[:role].find {|r| r[:name] == $1 }
        name = $2
      end
      incl_task = role[:task].find {|t| t[:name] == name }
      if incl_task == nil
        raise "Failed to find included task: #{name}.yml"
      end
      incl_task
    }
  end
end
