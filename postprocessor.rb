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
    role[:varset] ||= []
    role[:varset].each {|varset| do_vars(role, varset) }
    if role[:vardefaults] != nil
      # Consider defaults/main.yml just another source of var definitions
      vardefaults = role[:vardefaults][0]  # there can be only one
      vardefaults[:name] = '/vardefaults'
      do_vars(role, vardefaults)
      role[:varset].push vardefaults
      role.delete :vardefaults
    end
  end

  def do_vars(dict, varset)
    data = varset.delete :data
    varset[:var] = []
    data.keys.each {|varname|
      thing(varset, :var, varname, {:used => false, :defined => true})
    }
  end

  def do_playbook(dict, playbook)
    data = playbook.delete(:data)[0]
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
    data = task.delete :data
    role = task[:role]

    task[:included_tasks] = data.find_all {|i|
      i.is_a? Hash and i['include']
    }.map {|i| i['include'].split(" ")[0].sub(/\.yml$/, '')
    }.map {|n|
      role[:task].find {|t| t[:name] == n }
    }

    task[:included_varsets] = data.find_all {|i|
      i.is_a? Hash and i['include_vars']
    }.map {|i| i['include_vars'].split(" ")[0].sub(/\.yml$/, '')
    }.map {|n| role[:varset].find {|t| t[:name] == n } }

    task[:used_vars] = find_vars(data).uniq
    # TODO control this with a flag
    task[:used_vars] = task[:used_vars].map {|v|
      v =~ /(.*)_update$/ and $1 or v
    }.uniq

    # A fact is created by set_fact in a task. A fact defines a var for every
    # task which includes this task. Facts defined by the main task of a role
    # are defined for all tasks which include this role.
    data.map {|i| i['set_fact'] }.compact.flat_map {|i|
      if i.is_a? Hash
        i.keys
      else
        [i.split("=")[0]]
      end
    }.each {|n|
      used = task[:used_vars].include? n  # Just a first approximation
      thing(task, :var, n, {:role => role, :task => task, :used => used, :defined => true})
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
end
