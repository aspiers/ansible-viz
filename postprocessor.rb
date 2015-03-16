#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require 'ostruct'
require 'pp'


class Postprocessor
  # Most 'business logic' should live here, IE calculating fancy stuff.
  # Must ensure everything grapher expects is set, even if to empty []/{}.
  #
  # Vars can appear:
  #   * In role[:varset][:var], when defined in vars/
  #   * In role[:task][:var], when defined by set_fact
  #
  # Also task[:scope] exists

  def postprocess(dict)
    # Sweep up, collecting defined vars onto each role;
    # then sweep down checking all used vars are defined.
    # This may need to be oriented around tasks not roles >.<

    dict[:role].each_value {|role| do_role(dict, role) }

    todo = dict[:role].values
    bottomup = []
    while todo.length > 0
      role = todo.shift
      if role[:role_deps].all? {|dep| dep[:loaded] }
        role[:task].each_value {|t|
          calc_scope(dict, t)
        }
        role[:loaded] = true
        bottomup.push role
      else
        todo.push role
      end
    end
    bottomup.reverse.each {|r|
      r.delete :loaded
      check_used_vars(dict, r)
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
    role[:varset] ||= {}
    role[:varset].each_value {|varset| do_vars(role, varset) }
    role[:vardefaults] ||= {}
    role[:vardefaults].each_value {|varset| do_vars(role, varset) }
  end

  def calc_scope(dict, task)
    # This method must be called in bottom-up dependency order.
    role = task[:role]
    main_vs = role[:varset]["main"]
    role[:scope] = ((main_vs and main_vs[:var].values) or []) +
                   role[:role_deps].flat_map {|d| d[:scope] }
    task[:debug] = {
      :facts => task[:var].values,
      :role_scope => role[:scope],
      :incl_varsets => task[:included_varsets].flat_map {|vs| vs[:var].values },
      :incl_scopes => task[:included_tasks].flat_map {|t| t[:scope] }
    }
    task[:scope] = task[:debug].values.inject {|a,i| a + i }
  end

  def check_used_vars(dict, role)
    # This method must be called in top-down dependency order.
    # A var is used if a task from this role, or any role it depends on, refers to it
#    role[:used_vars] = role[:used_vars].map {|varname|
#      var = role[:defined_vars].find {|v| v[:name] == varname}
#      if var
#        var[:used] = true
#        var
#      else
#        thing(role, :var, varname, {:role => role, :used => true, :defined => false})
#      end
#    }
  end

  def do_vars(dict, varset)
    varset[:var] = {}
    varset[:data].keys.each {|varname|
      thing(varset, :var, varname, {:used => false, :defined => true})
    }
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
    data = task[:data]
    role = task[:role]

    task[:included_tasks] = data.find_all {|i|
      i.is_a? Hash and i['include']
    }.map {|i| i['include'].split(" ")[0].sub(/\.yml$/, '')
    }.map {|n|
      t = role[:task][n]
      if t == nil
        puts "Failed to find #{n}"
      end
      t
    }

    task[:included_varsets] = data.find_all {|i|
      i.is_a? Hash and i['include_vars']
    }.map {|i| i['include_vars'].split(" ")[0].sub(/\.yml$/, '')
    }.map {|n| role[:varset][n] }

    task[:used_vars] = find_vars(data).uniq

    # A fact is created by set_fact in a task. A fact defines a var for every
    # task which includes this task. Facts defined by the main task of a role
    # are defined for all tasks which include this role.
    task[:var] = {}
    task[:data].map {|i| i['set_fact'] }.compact.flat_map {|i|
      if i.is_a? Hash
        i.keys
      else
        [i.split("=")[0]]
      end
    }.reject {|n| 
    }.each {|n|
      used = task[:used_vars].include? n  # Just a first approximation
      thing(task, :var, n, {:role => role, :task => task, :used => used, :defined => true})
    }
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
