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
      raise "Failed to find role: #{rolename}"
  end
  def find_on_role(dict, role, type, name)
    role = if !role.is_a?(Hash) then find_role(dict, role) else role end
    role[type].find {|t| t[:name] == name } or
      raise "Failed to find #{type}: #{role[:name]}::#{name}"
  end

  def resolve_role_deps(dict, role)
    role[:role_deps] = role[:role_deps].map {|depname|
      begin
        find_role(dict, depname)
      rescue
        raise "Problem resolving deps for role #{role[:fqn]}: #{depname or 'nil'}"
      end
    }
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
        raise "Task #{task[:fqn]} failed to find included task: #{name}.yml"
      end
      incl_task
    }
  end

  def resolve_task_include_vars(dict, task)
    task[:included_varfiles].map! {|name|
      begin
        if name =~ %r!^([^/]+).yml!
          find_on_role(dict, task[:parent], :varfile, $1)
        elsif name =~ %r!^../vars/([^/]+).yml!
          find_on_role(dict, task[:parent], :varfile, $1)
        elsif name =~ %r!^../defaults/([^/]+).yml!
          find_on_role(dict, task[:parent], :vardefaults, $1)
        elsif name =~ %r!^../../([^/]+)/vars/([^/]+).yml!
          find_on_role(dict, $1, :varfile, $2)
        elsif name =~ %r!^../../([^/]+)/defaults/([^/]+).yml!
          find_on_role(dict, $1, :vardefaults, $2)
        else
          raise "Unhandled include_vars: #{name}"
        end
      rescue Exception => e
        puts "Problem resolving task '#{task[:fqn]}' include_vars: '#{name}'"
        raise
      end
    }
    if task[:included_varfiles].include?(nil)
      raise "Task #{task[:fqn]} has nil varfiles"
    end
  end
end
