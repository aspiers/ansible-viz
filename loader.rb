#!/usr/bin/ruby
# vim: set ts=2 sw=2:

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
        find_all { |file| /.yml$/i === file.downcase }
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
      map {|file| mk_playbook(dict, playbook_dir, file) }

    dict
  end

  def mk_role(dict, path, name)
    role = thing(dict, :role, name)

    # Get the names of roles which support this one with EG vars
    begin
      meta = Loader.yaml_slurp(path, name, "meta", "main.yml")
      role[:role_deps] = (meta['dependencies'] || []).
        map {|dep| dep['role'] }
    rescue Errno::ENOENT
      role[:role_deps] = []
    end

    vardir = File.join(path, name, "vars")
    Loader.ls_yml(vardir, []).
      map {|f| mk_varset(role, vardir, f) }

    vardefdir = File.join(path, name, "defaults")
    Loader.ls_yml(vardefdir, []).
      map {|f| mk_vardefaults(role, vardefdir, f) }

    taskdir = File.join(path, name, "tasks")
    Loader.ls_yml(taskdir, []).
      map {|f| mk_task(role, taskdir, f) }

    role
  end

  def mk_varset(role, path, file)
    name = file.sub(/.yml$/, '')
    data = Loader.yaml_slurp(path, file) || {}
    thing(role, :varset, name, {:data => data})
  end

  def mk_vardefaults(role, path, file)
    name = file.sub(/.yml$/, '')
    data = Loader.yaml_slurp(path, file) || {}
    thing(role, :vardefaults, name, {:data => data})
  end

  def mk_task(role, path, file)
    name = file.sub(/.yml$/, '')
    data = Loader.yaml_slurp(path, file) || []
    thing(role, :task, name, {:data => data})
  end

  def mk_playbook(dict, path, file)
    name = file.sub(/.yml$/, '')
    playbook = thing(dict, :playbook, name)
    playbook[:data] = Loader.yaml_slurp(path, file)
    playbook
  end
end
