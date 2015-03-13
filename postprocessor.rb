#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require 'ostruct'
require 'pp'


class Postprocessor
  # Responsible for establishing invariants on data, EG every ref should be present even if []/{}
  # Most 'business logic' should live here, IE calculating fancy stuff

  def postprocess(dict)
    # Sweep up, collecting defined vars onto each role;
    # then sweep down checking all used vars are defined.
    dict[:role].each_value {|role| do_role(dict, role) }
    todo = dict[:role].values
    bottomup = []
    while todo.length > 0
      role = todo.shift
      if role[:role_deps].all? {|dep| dep[:loaded] }
        calc_defined_vars(dict, role)
        role[:loaded] = true
        bottomup.push role
      else
        todo.push role
      end
    end
    bottomup.reverse.each {|r|
      r.delete :loaded
      check_used_vars(dict, r)
      push_used_vars_to_tasks(dict, r)
    }

    # Oh yeah process playbooks too
    dict[:playbook].each_value {|playbook| do_playbook(dict, playbook) }
  end

  def do_role(dict, role)
    role[:role_deps] = role[:role_deps].map {|depname|
      dep = dict[:role][depname]
      if dep == nil
        raise "Role '#{role[:name]}' failed to find dependency: #{depname}"
      end
      dep
    }

    role[:task] ||= {}
    role[:task].each_value {|task| do_task(dict, task) }
    role[:var] ||= {}
    role[:var].each_value {|var| do_var(dict, var) }
  end

  def calc_defined_vars(dict, role)
    # This method must be called in bottom-up dependency order.
    role[:defined_vars] = role[:var].values + role[:role_deps].flat_map {|dep| dep[:defined_vars] }

    role[:used_vars] = role[:task].each_value.flat_map {|task| task[:used_vars] }.uniq
    role[:used_vars] += role[:role_deps].flat_map {|dep| dep[:used_vars] }
    role[:fact] = role[:task].each_value.flat_map {|t| t[:fact] }
    role[:all_facts] = role[:fact] + role[:role_deps].flat_map {|dep| dep[:fact] }
  end

  def check_used_vars(dict, role)
    # This method must be called in top-down dependency order.
    # A var is used if a task from this role, or any role it depends on, refers to it
    role[:used_vars] = role[:used_vars].map {|varname|
      var = role[:defined_vars].find {|v| v[:name] == varname}
      if var
        var[:used] = true
        var
      else
        thing(role, :var, varname, {:role => role, :used => true, :defined => false})
      end
    }
  end

  def push_used_vars_to_tasks(dict, role)
    # Not 100% sure why I need this
    # After do_task, task[:used_vars] is a [String]. Convert to [Var].
#    vars_by_name = role[:used_vars].map {|v| [v[:name], v] }
#    role[:task].each {|t|
#      t[:used_vars] = t[:used_vars].map {|n| vars_by_name[n] }
#    }
  end

  def do_var(dict, var)
    # This only gets called on vars defined in a role. We'll work out whether it was really used later.
    var[:used] = false
    var[:defined] = true
  end

  def do_playbook(dict, playbook)
    data = playbook[:data][0]
    playbook[:role] = (data['roles'] || []).map {|role|
      if role.instance_of? Hash
        role = role['role']
      end
      dict[:role][role]
    }.uniq  # FIXME

    playbook[:task] = (data['tasks'] || []).map {|task_h|
      path = task_h['include'].split(" ")[0]
      if path !~ %r!roles/([^/]+)/tasks/([^/]+)\.yml!
        raise "Bad include from playbook #{playbook[:name]}: #{path}"
      end
      role, task = $1, $2
      dict[:role][role][:task][task]
    }.compact.uniq  # FIXME
  end

  def do_task(dict, task)
    task[:used_vars] = find_vars(task[:data]).uniq

    # A fact is created by set_fact in a task.
    # A var which is updated by set_fact is not what I'm calling a fact.
    task[:fact] = task[:data].map {|i| i['set_fact'] }.compact.flat_map {|i|
      if i.is_a? Hash
        i.keys
      else
        [i.split("=")[0]]
      end
    } - task[:used_vars]
  end

  def find_vars(data)
    if data.instance_of? Hash
      data.values.flat_map {|i| find_vars(i) }
    elsif data.is_a? Enumerable
      data.flat_map {|i| find_vars(i) }
    else
      # This really needs a proper parser
      fns = %w(join int item dirname basename regex_replace)
      data.to_s.scan(/\{\{\s*(.*?)\s*\}\}/).map {|m| m[0] }.
        map {|s|
          os = nil
          while os != s
            os = s
            s = s.gsub(/\w+\((.*?)\)/, '\1')
          end
          s
        }.
        flat_map {|s| s.split("|") }.
        reject {|s| s =~ /\w+\.stdout/ }.
        map {|s| s.split(".")[0] }.
        map {|s| s.split("[")[0] }.
        map {|s| s.gsub(/[^[:alnum:]_-]/, '') }.
        map {|s| s.strip }.
        reject {|s| fns.include? s }.
        reject {|s| s.empty? }
    end
  end
end
