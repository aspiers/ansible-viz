#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require 'ostruct'
require 'pp'


class Scoper
  # Most 'business logic' should live here, IE calculating fancy stuff.
  # Must ensure everything grapher expects is set, even if to empty []/{}.
  #
  # Vars can appear:
  #   * In role[:varset][:var], when defined in vars/
  #   * In role[:task][:var], when defined by set_fact
  #
  # Also task[:scope] exists

  def process(dict)
    # Sweep up, collecting defined vars onto each role;
    # then sweep down checking all used vars are defined.
    # This may need to be oriented around tasks not roles >.<

    find_var_usages(dict)

    order = order_tasks(dict[:role])
#    puts order.map {|r| r[:name] }.join(" ")
    order.each {|task|
      calc_scope(dict, task)
      task[:scope].each {|var|
        var[:used] = []
      }
    }
    order.reverse.each {|task|
      check_used_vars(dict, task)
    }
  end

  def find_var_usages(dict)
    dict[:role].each {|role|
      role[:task].each {|task|
        task[:used_vars] = find_vars(task[:data]).uniq
        # TODO control this with a flag
        task[:used_vars] = task[:used_vars].map {|v|
          v =~ /(.*)_update$/ and $1 or v
        }.uniq
      }
    }
  end

  def find_vars(data)
    if data.instance_of? Hash
      data.flat_map {|i| find_vars(i) }
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

  def order_list(list)
    # Dependency orders list
    todo = list.dup
    order = []
    safe = 0
    while todo.length > 0
      item = todo.shift
      deps = yield(item)
      if deps.all? {|dep| dep[:loaded] }
        item[:loaded] = true
        order.push item
      else
#        puts "Failed to process #{item[:fqn]}, deps: " + deps.map {|it| it[:name] }.join(" ")
        todo.push item
      end
      safe += 1
      if safe > 500
        oops = todo.map {|it| it[:fqn] }.join(" ")
        raise "oops: #{oops}"
      end
    end
    order.each {|i| i.delete :loaded }
    order
  end

  def order_tasks(roles)
    roles = order_list(roles) {|role| role[:role_deps] }
    all_tasks = roles.flat_map {|role|
      role[:task]
    }
    order_list(all_tasks) {|task|
      incl_tasks = task[:included_tasks].dup
      # :used_by_main is a pretty awful hack to break a circular scope dependency
      if task == task[:main_task]
        task[:included_tasks].each {|t| t[:used_by_main] == true }
      elsif not task[:used_by_main]
        incl_tasks += (task[:main_task] || [])
      end
      incl_tasks
    }
  end

  def calc_scope(dict, task)
    # This method must be called in bottom-up dependency order.
    role = task[:parent]
    if role[:scope] == nil
      main_vs = role[:varset].find {|vs| vs[:name] == 'main' } || {:var => []}
      vardefaults = role[:varset].find {|vs| vs[:type] == :vardefaults } || {:var => []}
      # role[:scope] should really only be set after the main task has been handled.
      # main can include other tasks though, so to break the circular dependency, allow
      # a partial role[:scope] of just the vars, defaults and dependent roles' scopes.
      role[:scope] = main_vs[:var] + vardefaults[:var] +
                     role[:role_deps].flat_map {|d| d[:scope] }
    end
    # This list must be in ascending precedence order
    task[:debug] = {
      :incl_varsets => task[:included_varsets].flat_map {|vs| vs[:var] },
      :incl_scopes => task[:included_tasks].flat_map {|t| t[:scope] },
      :role_scope => role[:scope],
      :facts => task[:var]
    }
    task[:scope] = task[:debug].values.inject {|a,i| a + i }
    if task == role[:main_task]
      # update the role[:scope] so it has the full picture
      role[:scope] = task[:scope]
    end
  end

  def check_used_vars(dict, task)
    # By this point, each task has a :scope of [Var].
    # We simply need to compare used_vars ([string]) with the vars and mark them used.
    scope_by_name = Hash[*(task[:scope].flat_map {|v| [v[:name], v] })]
    task[:used_vars].each {|use|
      var = scope_by_name[use]
      if var == nil
        var = thing(task, :var, use, {:defined => false})
      end
      var[:used] ||= []
      var[:used].push task
      task[:uses] ||= Set[]
      task[:uses].add var
    }
  end
end
