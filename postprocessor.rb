#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'ostruct'
require 'pp'


class Postprocessor
  def process(dict)
    dict[:role].each {|role| process_role(dict, role) }
    dict[:task] = dict[:role].flat_map {|role| role[:task] }
    dict[:playbook].each {|playbook| process_playbook(dict, playbook) }
  end

  def process_role(dict, role)
    role[:task] ||= []
    role[:task].each {|task| process_task(dict, task) }
    role[:main_task] = role[:task].find {|task| task[:name] == 'main' }

    role[:varfile] ||= []
    role[:varfile].each {|varfile| process_vars(role, varfile) }

    role[:vardefaults] ||= []
    role[:vardefaults].each {|varfile| process_vars(role, varfile) }
  end

  def process_vars(dict, varfile)
    data = varfile[:data]
    varfile[:var] = data.keys.map {|varname|
      thing(varfile, :var, varname, {:defined => true})
    }
  end

  def process_playbook(dict, playbook)
    data = playbook[:data][0]
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

  def process_task(dict, task)
    data = task[:data]

    task[:included_tasks] = data.find_all {|i|
      i.is_a? Hash and i['include']
    }.map {|i| i['include'].split(" ")[0] }

    task[:included_varfiles] = data.find_all {|i|
      i.is_a? Hash and i['include_vars']
    }.map {|i| i['include_vars'].split(" ")[0] }

    # A fact is created by set_fact in a task. A fact defines a var for every
    # task which includes this task. Facts defined by the main task of a role
    # are defined for all tasks which include this role.
    task[:var] = data.map {|i|
      i['set_fact']
    }.compact.flat_map {|i|
      if i.is_a? Hash
        i.keys
      else
        [i.split("=")[0]]
      end
    }.map {|n|
      thing(task, :var, n, {:defined => true})
    }
  end
end
