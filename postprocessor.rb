#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require 'ostruct'
require 'pp'


class Postprocessor
  def postprocess(dict)
    dict[:role].each_value {|role| do_role_1(dict, role) }
    todo = dict[:role].values
    while length(todo) > 0
      role = todo.unshift
      if role[:role_deps].all? {|dep| dep[:loaded] }
        do_role_2(dict, todo[0])
      else
        todo.push role
      end
    end
    dict[:playbook].each_value {|playbook| do_playbook(dict, playbook) }
  end

  def do_role_1(dict, role)
    role[:role_deps] = role[:role_deps].map {|depname|
      dep = dict[:role][depname]
      if dep == nil
        raise "Role '#{role[:name]}' failed to find dependency: #{depname}"
      end
      dep
    }

    role[:task].each_value {|task| do_task(dict, task) }
    role[:var].each_value {|var| do_var(dict, var) }
  end

  def do_role_2(dict, role)

    role[:used_vars] = role[:task].each_value.flat_map {|task| task[:used_vars] }.uniq
#    role[:used_vars] += role[:role_deps].flat_map {|dep| dep[:used_vars] }
#    role[:facts] = role[:task].flat_map {|t| t[:facts] }
#    role[:facts] += role[:role_deps].flat_map {|dep| dep[:facts] }
#    role[:unused_vars] = (role[:var] - role[:used_vars]).reject {|v|
#      role[:facts].include? v[:name]
#    }
#    role[:undefed_vars] = role[:used_vars] - role[:var]
  end

  def do_var(dict, var)
  end

  def do_playbook(dict, playbook)
    data = playbook[:data][0]
    playbook[:roles] = (data['roles'] || []).map {|role|
      if role.instance_of? Hash
        role = role['role']
      end
      dict[:role][role]
    }.uniq  # FIXME

    playbook[:tasks] = (data['tasks'] || []).map {|task_h|
      path = task_h['include'].split(" ")[0]
      if path !~ %r!roles/([^/]+)/tasks/([^/]+)\.yml!
        raise "Bad include from playbook #{playbook[:name]}: #{path}"
      end
      role, task = $1, $2
      dict[:role][role][:task][task]
    }.compact.uniq  # FIXME
  end

  def do_task(dict, task)
    task[:facts] = task[:data].map {|i| i['set_fact'] }.compact.flat_map {|i|
      if i.is_a? Hash
        i.keys
      else
        [i.split("=")[0]]
      end
    }

    task[:used_vars] = find_vars(task[:data]).reject {|varname|
      task[:facts].include? varname
    }.uniq
  end

  def find_vars(data)
    if data.instance_of? Hash
      data.values.flat_map {|i| find_vars(i) }
    elsif data.is_a? Enumerable
      data.flat_map {|i| find_vars(i) }
    else
      # This really needs a proper parser
      fns = ["join", "int", "item", "dirname", "basename", "regex_replace"]
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
