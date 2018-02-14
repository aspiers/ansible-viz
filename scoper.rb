#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'ostruct'
require 'pp'
require 'word_wrap'
require 'word_wrap/core_ext'


class Scoper
  # Most 'business logic' should live here, IE calculating fancy stuff.
  # Must ensure everything grapher expects is set, even if to empty []/{}.
  #
  # Vars can appear:
  #   * In role[:varfile][:var], when defined in vars/
  #   * In role[:task][:var], when defined by set_fact
  #
  # Also task[:scope] exists

  def process(dict)
    # Sweep up, collecting defined vars onto each role;
    # then sweep down checking all used vars are defined.

    bottomup = order_tasks(dict[:role])
    topdown = bottomup.reverse

    topdown.each {|task|
      # Copy :args down to every task this one includes
      task[:included_tasks].each {|t| t[:args] += task[:args] }
    }

    debug 2, "Calculating scope for each task, bottom up"
    bottomup.each {|task|
      # Exclude "vars" which are actually registered resultsets
      task[:registers] = find_registers(task, task[:data])
      task[:registers] += task[:included_tasks].flat_map {|t| t[:registers] }
      task[:used_vars].reject! {|s| task[:registers].include? s }

      calc_scope(dict, task)
      task[:scope].each {|var|
        var[:used] = []
      }
    }

    debug 2, "Checking used vars for each task, top down"
    topdown.each {|task|
      check_used_vars_for_task(dict, task)
    }

    # Construct a mapping of variable names to variables for all variables
    # in all tasks/varfiles/vardefaults of every role
    pairs = dict[:role].flat_map {|role|
      [:task, :varfile, :vardefaults].
        flat_map {|sym| role[sym] }.
        flat_map {|t| t[:var] }.
        flat_map {|v| [v[:name], v] }
    }
    # FIXME this works but shows vars are not always unified correctly.
    # Might not be fixable for facts?
#    counts = pairs.group_by {|k,v| k }.map {|k,v| [k, v.count] }
#    counts.each {|k, v| puts "! #{v} vars with same name: #{k}" if v > 1 }
    dict[:vars_by_name] = Hash[*pairs]
    dict[:role].each {|role|
      [:varfile, :vardefaults, :template].
        flat_map {|sym| role[sym] }.
        each {|vf| check_used_vars(dict, vf) }
    }
  end

  def find_registers(task, data)
    VarFinder.walk(data) {|type, obj|
      case type
      when :hash
        [obj['register']]
      end
    }
  end

  def wrap_indent(indent, list)
    list.join(" ") \
      .wrap(tty_width - indent.size) \
      .gsub(/^/, indent)
  end

  # Take a list of roles or tasks, and return another list of the same
  # items topologically sorted so that dependencies come before the
  # items which depend on them.
  #
  # Requires a block to be passed which when called with a given role
  # or task, will return an Array of its dependencies.
  def order_list(type, list)
    debug 3, "order_list() ordering #{type}s"
    debug 4, "   [\n" +
             wrap_indent(' ' * 6, list.map { |item| item[:fqn] }) +
             "   ]"
    todo = list.dup
    order = []
    safe = 0
    while todo.length > 0
      item = todo.shift
      debug 4, "   order_list() processing #{type} '#{item[:fqn]}', " \
               "#{todo.length} still todo"
      deps = yield(item)
      deps.reject! {|i|
        (i.is_a?(String) && i =~ /dynamic dependency/) or
        (i.is_a?(Hash) && i[:unresolved])
      }
      if deps.all? {|dep|
           unless dep.is_a? Hash
             raise "weird dep of #{type} '#{item[:fqn]}': #{dep.inspect}"
           end
           dep[:loaded]
         }
        item[:loaded] = true
        debug 5, "      All #{deps.size} dependencies of #{type} '#{item[:fqn]}' loaded, "\
                 "pushing onto order"
        order.push item
      else
        debug 5, "      Deps of #{type} '#{item[:fqn]}' not all loaded:\n" +
                 wrap_indent(' ' * 9, deps.map {|it| it[:name] })
        debug 5, "      Pushing to back of todo list"
        todo.push item
      end
      safe += 1
      if safe > 500
        oops = todo.map {|it| it[:fqn] }.join(" ")
        raise "Oops, infinite recursion?\nTodo list was: #{oops}"
      end
    end
    order.each {|i| i.delete :loaded }
    debug 4, "Final order of #{type}s:\n" +
             wrap_indent(' ' * 3, list.map { |item| item[:fqn] })
    order
  end

  def all_tasks(roles)
    roles = order_list("role", roles) {|role| role[:role_deps] }
    roles.flat_map {|role| role[:task] }
  end

  def order_tasks(roles)
    order_list("task", all_tasks(roles)) {|task|
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

  def raise_if_nil(context, name, it)
    if it.nil?
      raise "in #{context}, #{name} is nil"
    elsif it.include? nil
      raise "in #{context}, #{name} #{it.class} includes nil"
    end
  end

  # Calculate scope of task, i.e. which variables are available to the task.
  # This method must be called in bottom-up dependency order.
  def calc_scope(dict, task)
    role = task[:parent]
    debug 3, "calc_scope(#{task[:fqn]}), parent #{role[:fqn]}"
    if role[:scope].nil?
      debug 4, "   no scope for #{role[:fqn]} yet"
      main_vf = role[:varfile].find {|vf| vf[:name] == 'main' } || {:var => []}
      raise_if_nil(task[:fqn], "main_vf", main_vf)

      defaults = role[:vardefaults].flat_map {|vf| vf[:var] }
      raise_if_nil(task[:fqn], "defaults", defaults)

      # role[:scope] should really only be set after the main task has
      # been handled.  main can include other tasks though, so to
      # break the circular dependency, allow a partial role[:scope] of
      # just the vars, defaults and dependent roles' scopes.
      dep_vars = role[:role_deps].flat_map {|dep|
        debug 5, "Checking dependency '#{dep[:fqn]}' of " +
                 "role '#{role[:fqn]}'"

        if ! dep.has_key? :scope
          debug 1, "WARNING: dependency '#{dep[:fqn]}' of " +
                   "role '#{role[:fqn]}' is missing scope; " +
                   "guessing that it didn't have any tasks."
          nil
        else
          debug 5, "   dependency '#{dep[:fqn]}' of role '#{role[:fqn]}' " +
                   "has scope:\n" +
                   wrap_indent(' ' * 6, dep[:scope].map {|i| i[:fqn]})
          dep[:scope]
        end
      }.compact
      raise_if_nil(task[:fqn], "dependency scope", dep_vars)
      role[:scope] = main_vf[:var] + defaults + dep_vars
    end

    # This list must be in ascending precedence order
    task[:debug] = {
      :incl_varfiles => task[:included_varfiles].flat_map {|vf| vf[:var] },
      :args => task[:args],
      :incl_scopes => task[:included_tasks].flat_map {|t|
        raise "task '#{t[:fqn]}' missing scope" unless t[:scope]
        t[:scope]
      },
      :role_scope => role[:scope],
      :facts => task[:var]
    }
    task[:debug].each {|k,v| raise_if_nil(task[:fqn], k, v) }
    task[:scope] = task[:debug].values.inject {|a,i| a + i }
    if task == role[:main_task]
      # update the role[:scope] so it has the full picture
      role[:scope] = task[:scope]
      debug 4, "   set full scope for role '#{role[:fqn]}' from task '#{task[:fqn]}'"
    end
  end

  def check_used_vars_for_task(dict, task)
    # By this point, each task has a :scope of [Var].
    # We simply need to compare used_vars ([string]) with the vars and mark them used.
    scope_by_name = Hash[*(task[:scope].flat_map {|v| [v[:name], v] })]
    task[:used_vars].each {|use|
      var = scope_by_name[use]
      if var.nil?
        var = thing(task, :var, use, task[:path], {:defined => false})
      end
      var[:used] ||= []
      var[:used].push task
      task[:uses] ||= Set[]
      task[:uses].add var
    }
  end

  def check_used_vars(dict, thing)
    thing[:used_vars].each {|use|
      # Figuring out the varfile scope is pretty awful since it could be included
      # from anywhere. Let's just mark vars used.
      var = (thing[:var] || []).find {|v| v[:name] == use }
      if var.nil?
        # Using a heuristic of "if you have two vars with the same name
        # then you're a damned fool".
        var = dict[:vars_by_name][use]
      end
      if var.nil?
#        puts "Can't find var anywhere: #{use}"
        next
      end
      var[:used] ||= []
      var[:used].push thing
      thing[:uses] ||= Set[]
      thing[:uses].add var
#      puts "#{thing[:fqn]} -> #{var[:fqn]}"
    }
  end
end
