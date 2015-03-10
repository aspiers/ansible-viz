#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require 'mustache'
require 'yaml'
require 'fileutils'
require 'ostruct'
require 'pp'


########## UTILS #############

def thing(dict, type, name, extra = {})
  dict[type] ||= {}
  it = dict[type][name]
  if !it
    it = {:type => type, :name => name}
    dict[type][name] = it
  end
  it.merge!(extra)
  it
end

def ls(path, default=nil)
  if !File.directory? path
    if default == nil
      raise "No such directory: " + path
    end
    return default
  end
  Dir.new(path).reject {|f| f =~ /^\./ }
end

def yaml_slurp(*steps)
  filepath = File.join(*steps)
  File.open(filepath) {|fd|
    return YAML.load(fd)
  }
end

########## LOAD DATA #############
# TODO slurp all YAML up-front, then process
# TODO tests...

class Loader
  def load_dir(playbook_dir)
    dict = {}

    # Load all roles first, before playbooks.
    # This will also bring in tasks and vars.
    rolesdir = File.join(playbook_dir, "roles")
    ls(rolesdir).find_all { |file| File.directory?(File.join(rolesdir, file)) }.
        map {|file| mk_role(dict, rolesdir, file) }

    # Load playbooks
    ls(playbook_dir).find_all { |file|
      /.yml$/i === file.downcase
    }.map { |file| mk_playbook(dict, playbook_dir, file) }

    postprocess(dict)
  end

  def mk_role(dict, path, name)
    role = thing(dict, :role, name)

    # Load roles which support this one, EG with vars
    begin
      meta = yaml_slurp(path, name, "meta", "main.yml")
      role[:role_deps] = (meta['dependencies'] || []).
        map {|dep| dep['role'] }.
        map {|dep| mk_role(dict, path, dep) }
    rescue Errno::ENOENT
      role[:role_deps] = []
    end

    # Load vars before tasks, so they're available in dict
    vardir = File.join(path, name, "vars")
    role[:vars] = ls(vardir, []).
      find_all {|f| f =~ /\.yml$/ }.
      flat_map {|f| mk_vars(dict, vardir, f) }.
      uniq  # FIXME

    taskdir = File.join(path, name, "tasks")
    role[:tasks] = ls(taskdir, []).
      find_all {|f| f =~ /\.yml$/ }.
      map {|f| mk_task(dict, taskdir, f) }.
      uniq  # FIXME

    role
  end

  def mk_task(dict, path, file)
    name = file.sub(/.yml$/, '')
    if path !~ %r!roles/([[:alnum:]_-]+)!
      raise "Bad task path: "+ path
    end
    rolename = $1
    long = "Task " + rolename + "::" + name
    task = thing(dict, :task, long, {:role => rolename, :label => name})

    taskdata = yaml_slurp(path, file) || []
    task[:facts] = taskdata.map {|i| i['set_fact'] }.compact.flat_map {|i|
      if i.is_a? Hash
        i.keys
      else
        [i.split("=")[0]]
      end
    }
    task[:used_vars] = find_vars(taskdata).reject {|varname|
      task[:facts].include? varname
    }.map {|varname|
      mk_var(dict, rolename, varname)
    }.uniq

    task
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

  def mk_vars(dict, path, file)
    if !File.file? File.join(path, file) then
      return []
    end

    vardata = yaml_slurp(path, file)
    path =~ %r!roles/([[:alnum:]_-]+)!
    rolename = $1
    (vardata || {}).keys.map {|key|
      mk_var(dict, rolename, key)
    }
  end

  def mk_var(dict, rolename, name)
  #  if name == "vagrant_plugins"
  #    1/0
  #  end
    long = "Var " + rolename + "::" + name
    thing(dict, :var, long, {:role => $1, :label => name})
  end

  def mk_playbook(dict, path, file)
    name = file.sub(/.yml$/, '')
    playbook = thing(dict, :playbook, name)
    data = yaml_slurp(path, file)
    playbook[:roles] = (data[0]['roles'] || []).map {|role|
      if role.instance_of? Hash
        role = role['role']
      end
      # All roles should be loaded already
      dict[:role][role]
    }.uniq  # FIXME

    playbook[:tasks] = (data[0]['tasks'] || []).map {|task_h|
      rel_path = task_h['include'].split(" ")[0]
      file = File.basename(rel_path)
      taskdir = File.dirname(File.join(path, rel_path))
      mk_task(dict, taskdir, file)
    }.compact.uniq  # FIXME
    playbook
  end

  def postprocess(dict)
    dict[:role].each_value {|role|
      role[:used_vars] = role[:tasks].flat_map {|task| task[:used_vars] }.uniq
      role[:used_vars] += role[:role_deps].flat_map {|dep| dep[:used_vars] }
      role[:facts] = role[:tasks].flat_map {|t| t[:facts] }
      role[:facts] += role[:role_deps].flat_map {|dep| dep[:facts] }
      role[:unused_vars] = (role[:vars] - role[:used_vars]).reject {|v|
        role[:facts].include? v[:label]
      }
      role[:undefed_vars] = role[:used_vars] - role[:vars]
    }

    dict
  end
end
