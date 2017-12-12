#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'ostruct'
require 'pp'


class Postprocessor
  def initialize(options)
    @options = options
  end

  def process(dict)
    dict[:role].each {|role| process_role(dict, role) }
    dict[:task] = dict[:role].flat_map {|role| role[:task] }
    # Must process playbooks after tasks
    dict[:playbook].each {|playbook| process_playbook(dict, playbook) }
  end

  def process_role(dict, role)
    role[:task] ||= []
    role[:task].each {|task| process_task(dict, task) }
    role[:main_task] = role[:task].find {|task| task[:name] == 'main' }

    [:varfile, :vardefaults].each {|type|
      role[type] ||= []
      role[type].each {|varfile| process_vars(role, varfile) }
    }

    role[:template] ||= []
  end

  def process_vars(dict, varfile)
    data = varfile[:data]
    varfile[:var] = data.each.flat_map {|key, value|
      if key =~ /(_default|_updates)$/
        []
      else
        [thing(varfile, :var, key, varfile[:path], {:defined => true, :data => value})]
      end
    }
  end

  # Parse an argument string like "aa=11 bb=2{{ cc }}/{{ dd }}2",
  # replace interpolations with "x" to obtain "aa=11 bb=2x2", then
  # convert to a Hash: {'aa' => "11", 'bb' => '2x2'}
  def parse_args(s)
    s.gsub(/{{(.*?)}}/, "x").
      split(" ").
      map {|i| i.split("=") }.
      reduce({}) {|acc, pair| acc.merge(Hash[*pair]) }
  end

  # Parse an include directive of the form:
  #
  #   foo.yml param1=bar1 param2=bar2 tags=qux
  #
  # discarding any "tags" parameter, and return:
  #
  #   ["foo.yml", { "param1" => "bar1", "param2" => "bar2" }]
  def parse_include(s)
    s.gsub! /\{\{\s*playbook_dir\s*\}\}\//, ''
    if s =~ /\{\{.*\}\}/
        $stderr.puts "WARNING: not parsing dynamic include of #{role[:name]} " +
                     "role on:\n" +
                     depname + "\n" +
                     "since expressions are not supported yet."
        return [s, {}]
    end

    elements = s.split(" ")
    taskname = elements.shift
    args = parse_args(elements.join(" ")).keys.reject {|k| k == 'tags' }
    [taskname, args]
  end

  def process_playbook(dict, playbook)
    debug 3, "process_playbook(#{playbook[:fqn]})"
    debug 5, playbook.pretty_inspect.gsub(/^/, '   ')
    playbook[:include] = []
    playbook[:role] = []
    playbook[:task] = []

    playbook[:data].each {|data|
      if data.keys.include? 'include'
        playbook[:include].push data['include']
      end

      playbook[:role] += (data['roles'] || []).map {|role_or_name|
        role_name = role_or_name.instance_of?(Hash) ?
                      role_or_name['role'] : role_or_name
        role = dict[:role].find {|r| r[:name] == role_name }
        unless role
          $stderr.puts "WARNING: Couldn't find role '#{role_name}' "\
                       "(invoked by playbook '#{playbook[:name]}')"
        end
        role
      }.compact

      playbook[:task] += (data['tasks'] || []).map {|task_hash|
        next nil unless task_hash['include']
        debug 5, "   adding task #{task_hash}"
        path, args = parse_include(task_hash['include'])
        if path !~ %r!roles/([^/]+)/tasks/([^/]+)\.yml!
          raise "Bad include from playbook #{playbook[:name]}: #{path}"
        end
        rolename, taskname = $1, $2
        role = dict[:role].find {|r| r[:name] == rolename }
        debug 4, "   found task's role #{role[:fqn]}"
        task = role[:task].find {|t| t[:name] == taskname }
        debug 4, "   found task #{taskname}"
        task[:args] += args
        task
      }.compact
    }

    playbook[:task].uniq!
  end

  def process_task(dict, task)
    data = task[:data]

    task[:args] = []
    task[:included_by_tasks] = []

    task[:included_tasks] = data.find_all {|i|
      i.is_a? Hash and i['include']
    }.map {|i| parse_include(i['include']) }

    task[:included_varfiles] = data.find_all {|i|
      i.is_a? Hash and i['include_vars']
    }.map {|i| i['include_vars'] }

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
      thing(task, :var, n, task[:path], {:defined => true})
    }

    task[:used_templates] = data.flat_map {|subtask|
      if subtask.include?("template")
        line = subtask["template"]
        args = case line
               when Hash then line
               when String then parse_args(line)
               else raise "Bad type: #{line.class}"
               end
        [args["src"].sub(/(.*)\..*/, '\1')]
      else []
      end
    }
    if task[:used_templates].length > 0
      debug 6, task[:used_templates].pretty_inspect
    end
  end
end
