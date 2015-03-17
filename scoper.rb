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

    bottomup = dep_order(dict[:role])
    bottomup.each {|role|
      role[:task].each {|t|
        calc_scope(dict, t)
      }
    }
    bottomup.reverse.each {|r|
      r.delete :loaded
      check_used_vars(dict, r)
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

  def dep_order(roles)
    todo = roles.dup
    bottomup = []
    while todo.length > 0
      role = todo.shift
      if role[:role_deps].all? {|dep| dep[:loaded] }
        role[:loaded] = true
        bottomup.push role
      else
        todo.push role
      end
    end
    bottomup.each {|r| r.delete :loaded }
  end

  def calc_scope(dict, task)
    # This method must be called in bottom-up dependency order.
    role = task[:parent]
    main_vs = role[:varset].find {|vs| vs[:name] == 'main' } || {:var => []}
    vardefaults = role[:varset].find {|vs| vs[:type] == :vardefaults } || {:var => []}
    role[:scope] = main_vs[:var] + vardefaults[:var] +
                   role[:role_deps].flat_map {|d| d[:scope] }
    task[:debug] = {
      :facts => task[:var],
      :role_scope => role[:scope],
      :incl_varsets => task[:included_varsets].flat_map {|vs| vs[:var] },
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
end
