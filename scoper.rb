#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'ostruct'
require 'pp'


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
    # This may need to be oriented around tasks not roles >.<

    find_var_uses(dict)

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

  def find_var_uses(dict)
    dict[:role].each {|role|
      role[:task].each {|task|
        task[:used_vars] = find_vars(task, task[:data]).uniq

        # Exclude "vars" which are actually registered resultsets
        registers = find_registers(task, task[:data])
        task[:used_vars].reject! {|s| registers.include? s }

        # TODO control this with a flag
        task[:used_vars] = task[:used_vars].flat_map {|v|
          v =~ /(_default|_updates)$/ and [] or [v]
        }.uniq

        raise_if_nil("#{task[:fqn]} used vars", task[:used_vars])
      }
    }
  end

  def walk(tree, &block)
    case tree
    when Hash
      res = (yield(:hash, tree) or [])
      res + tree.flat_map {|k,v| walk(v, &block) }.compact
    when Enumerable
      res = (yield(:list, tree) or [])
      res + tree.flat_map {|i| walk(i, &block) }.compact
    else
      yield(:scalar, tree)
    end
  end

  def find_registers(task, data)
    walk(data) {|type, obj|
      case type
      when :hash
        [obj['register']]
      end
    }
  end

  def find_vars(task, data)
    walk(data) {|type, obj|
      case type
      when :hash
        find_vars_in_with_and_when(task, obj)
      when :scalar
        find_vars_in_string(obj)
      end
    }
  end

  def find_vars_in_string(data)
    # This really needs a proper parser. For example, it can't handle nested {{ }}
    # and it strips strings really badly.
    # Maybe use the Python ast module? Oh wait we're in Ruby.
    # rubypython gem didn't work for me, with Ruby 1.9.3 or 2.2.1.
    rej = %w(ansible_env join int item dirname basename regex_replace search
             is defined failed skipped success True False update in
             vagrant_version Vagrant)
    data.to_s.scan(/\{\{\s*(.*?)\s*\}\}/).
      map {|m| m[0] }.
#      map {|s| if s =~ /virsh_vol_list_result/ then pp s end; s }.
      map {|s|
        # Turn all "f(x)" into "x", vars can't be function names
        os = nil
        while os != s
          os = s
          s = s.gsub(/\w+\((.*?)\)/, '\1')
        end
        s
      }.
      flat_map {|s| s.gsub(/".*?"/, "") }.
      flat_map {|s| s.gsub(/'.*?'/, "") }.
      flat_map {|s| s.gsub(/not /, "") }.
      flat_map {|s| s.split("|") }.
      flat_map {|s| s.split(" and ") }.
      flat_map {|s| s.split(" or ") }.
      flat_map {|s| s.split(" ") }.
      reject {|s| s =~ /\w+\.stdout/ }.
      map {|s| s.split(".")[0] }.
      map {|s| s.split("[")[0] }.
      map {|s| s.gsub(/[^[:alnum:]_-]/, '') }.
      reject {|s| rej.include? s }.
      reject {|s| s =~ /^\d*$/ }.
      reject {|s| s.empty? }
  end

  def find_vars_in_with_and_when(task, data)
    items = data['with_items'] || []
    items = if items.is_a?(String)
      find_vars_in_string("{{ #{items} }}")
    else
      items.flat_map {|s| find_vars_in_string(s) }
    end

    with_dict = [data['with_dict']].flat_map {|s|
      find_vars_in_string("{{ #{s} }}")
    }
#    if with_dict.length > 0 then pp with_dict end

    _when = [data['when']].flat_map {|s|
      find_vars_in_string("{{ #{s} }}")
    }
#    if _when.length > 0 then pp _when end

    items + with_dict + _when
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

  def raise_if_nil(name, it)
    if it == nil
      raise "#{name} is nil"
    elsif it.include? nil
      raise "#{name} includes nil"
    end
  end

  def calc_scope(dict, task)
    # This method must be called in bottom-up dependency order.
    role = task[:parent]
    if role[:scope] == nil
      main_vf = role[:varfile].find {|vf| vf[:name] == 'main' } || {:var => []}
      raise_if_nil("main_vf", main_vf)

      defaults = role[:vardefaults].flat_map {|vf| vf[:var] }
      raise_if_nil("defaults", defaults)

      # role[:scope] should really only be set after the main task has been handled.
      # main can include other tasks though, so to break the circular dependency, allow
      # a partial role[:scope] of just the vars, defaults and dependent roles' scopes.
      role[:scope] = main_vf[:var] + defaults +
                     role[:role_deps].flat_map {|d| d[:scope] }
    end
    # This list must be in ascending precedence order
    task[:debug] = {
      :incl_varfiles => task[:included_varfiles].flat_map {|vf| vf[:var] },
      :incl_scopes => task[:included_tasks].flat_map {|t| t[:scope] },
      :role_scope => role[:scope],
      :facts => task[:var]
    }
    task[:debug].each {|k,v| raise_if_nil(k, v) }
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
