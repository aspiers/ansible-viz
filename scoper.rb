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

    return

    todo = dict[:role]
    bottomup = []
    while todo.length > 0
      role = todo.shift
      if role[:role_deps].all? {|dep| dep[:loaded] }
        role[:task].each {|t|
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
  end

  def calc_scope(dict, task)
    # This method must be called in bottom-up dependency order.
    role = task[:role]
    main_vs = role[:varset]["main"]
    role[:scope] = ((main_vs and main_vs[:var]) or []) +
                   role[:role_deps].flat_map {|d| d[:scope] }
    task[:debug] = {
      :facts => task[:var],
      :role_scope => role[:scope],
      :incl_varsets => task[:included_varsets].flat_map {|vs| vs[:var] },
      :incl_scopes => task[:included_tasks].flat_map {|t| t[:scope] }
    }
    task[:scope] = task[:debug].inject {|a,i| a + i }
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
