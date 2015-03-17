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
    while todo.length > 0
      item = todo.shift
      if yield(item).all? {|dep| dep[:loaded] }
        item[:loaded] = true
        order.push item
      else
        todo.push item
      end
    end
    order.each {|i| i.delete :loaded }
    order
  end

  def order_tasks(roles)
    roles = order_list(roles) {|role| role[:role_deps] }
    roles.flat_map {|role|
      order_list(role[:task]) {|task|
        main_task = if task[:name] == 'main' then []
                    else task[:parent][:task].find_all {|t| t[:name] == 'main' }
                    end
        task[:included_tasks] + main_task
      }
    }
  end

  def calc_scope(dict, task)
    # This method must be called in bottom-up dependency order.
    role = task[:parent]
    if task[:name] == 'main'
      main_vs = role[:varset].find {|vs| vs[:name] == 'main' } || {:var => []}
      vardefaults = role[:varset].find {|vs| vs[:type] == :vardefaults } || {:var => []}
      role_scope = main_vs[:var] + vardefaults[:var] +
                     role[:role_deps].flat_map {|d| d[:scope] }
    else
      role_scope = role[:scope]
    end
    # Must be in ascending precedence order
    task[:debug] = {
      :incl_varsets => task[:included_varsets].flat_map {|vs| vs[:var] },
      :incl_scopes => task[:included_tasks].flat_map {|t| t[:scope] },
      :role_scope => role_scope,
      :facts => task[:var]
    }
    task[:scope] = task[:debug].values.inject {|a,i| a + i }
    if task[:name] == 'main'
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
    }
  end
end
