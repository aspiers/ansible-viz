#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'mustache'
require 'yaml'
require 'fileutils'
require 'ostruct'
require 'pp'


def thing(parent, type, name, extra = {})
  it = {:type => type, :name => name, :fqn => name}.merge(extra)
  if parent[:type] != nil
    it.merge!({:parent => parent,
               :fqn => "#{parent[:fqn]}::#{name}"})
  end
  parent[type] ||= []
  parent[type].push it
  it
end


class Loader
  # Creates things for playbooks, roles, tasks and varfiles.
  # Vars in role/defaults/main.yml are provided as a varfile with type :vardefaults.
  # Includes are noted by name/path, not turned into thing refs.

  class <<self
    def ls(path, default=nil)
      if !File.directory? path
        if default == nil
          raise "No such directory: " + path
        end
        return default
      end
      Dir.new(path).reject {|f| f =~ /^\./ }
    end

    def ls_yml(path, default=nil)
      ls(path, default).
        find_all { |file| /\.yml$/i === file.downcase }
    end

    def yaml_slurp(*steps)
      filepath = File.join(*steps)
      File.open(filepath) {|fd|
        return YAML.load(fd)
      }
    end
  end

  def load_dir(playbook_dir)
    dict = {}

    rolesdir = File.join(playbook_dir, "roles")
    Loader.ls(rolesdir).
      find_all { |file| File.directory?(File.join(rolesdir, file)) }.
      map {|file| mk_role(dict, rolesdir, file) }

    Loader.ls_yml(playbook_dir).
      map {|file| load_thing(dict, :playbook, playbook_dir, file) }

    dict
  end

  def mk_role(dict, path, name)
    role = thing(dict, :role, name)

    # Get the names of roles which support this one with EG vars
    begin
      meta = Loader.yaml_slurp(path, name, "meta", "main.yml")
      role[:role_deps] = ((meta && meta['dependencies']) || []).
        map {|dep| dep.is_a?(Hash) and dep['role'] or dep }
    rescue Errno::ENOENT
      role[:role_deps] = []
    end

    {:varfile => "vars",
     :vardefaults => "defaults",
     :task => "tasks",
    }.each_pair {|type, dirname|
      dir = File.join(path, name, dirname)
      Loader.ls_yml(dir, []).map {|f|
        load_thing(role, type, dir, f) }
    }

    dir = File.join(path, name, "templates")
    Loader.ls(dir, []).map {|f|
      name = File.basename(f, '.*')
      data = File.readlines(File.join(dir, f))
      thing(role, :template, name, {:data => data})
    }

    role
  end

  def load_thing(parent, type, path, file)
    name = File.basename(file, '.*')
    data = Loader.yaml_slurp(path, file) || {}
    thing(parent, type, name, {:data => data})
  end
end
