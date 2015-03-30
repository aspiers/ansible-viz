#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'ostruct'
require 'pp'


class Resolver
  # Converts includes from names/paths to things.
  # Ensure you've loaded the whole bag before trying to resolve it.

  def process(dict)
    dict[:role].each {|role|
      resolve_role_deps(dict, role)
    }
    dict[:task].each {|task|
      resolve_task_includes(dict, task)
      resolve_task_include_vars(dict, task)
    }
  end

  def find_role(dict, rolename)
    dict[:role].find {|r| r[:name] == rolename } or
      raise "Failed to find role '#{rolename}'"
  end
  def find_task(dict, rolename, taskname)
    find_role(rolename).find {|t| t[:name] == taskname } or
      raise "Failed to find task '#{rolename}::#{taskname}'"
  end
  def find_varfile(dict, rolename, varfilename)
    find_role(rolename).find {|vf| vf[:name] == varfilename } or
      raise "Failed to find varfile '#{rolename}::#{varfilename}'"
  end

  def resolve_role_deps(dict, role)
    role[:role_deps] = role[:role_deps].map {|depname|
      find_role(dict, depname)    }
  end

  def resolve_task_includes(dict, task)
    task[:included_tasks].map! {|name|
      role = task[:parent]
      if name =~ %r!../../([^/]+)/tasks/([^/]+.yml)!
        role = dict[:role].find {|r| r[:name] == $1 }
        name = $2
      end
      name.sub!(/\.yml$/, '')
      incl_task = role[:task].find {|t| t[:name] == name }
      if incl_task == nil
        raise "Failed to find included task: #{name}.yml"
      end
      incl_task
    }
  end

  def resolve_task_include_vars(dict, task)
    task[:included_varfiles].map! {|n|
      task[:parent][:varfile].find {|t| t[:name] == n.sub(/\.yml$/, '') }
    }
  end
end
