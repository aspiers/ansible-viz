#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require './graphviz'
require 'mustache'
require 'yaml'
require 'fileutils'
require 'optparse'
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

def load_data(options)
  dict = {}

  # Load all roles first, before playbooks.
  # This will also bring in tasks and vars.
  playbook_dir = options.playbook_dir
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

#pp find_vars("abc {{def}} ghi")
#pp find_vars(["{{1}}", "{{2}}"])
#pp find_vars({:a => "{{1}}", :b => "{{2}}"})
#pp find_vars({:a => ["{{1}}", "{{2}}"], :b => "{{3}}"})
#pp find_vars("{{1|up(2)}}")
#pp find_vars("{{ccache | update(ccache_update | default({}))}}")
#1/0

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


########## GRAPHIFY ###########

def graphify(dict, options)
  # FIXME Cosmetic stuff should be in decorate_* methods

  g = Graph.new
  g[:rankdir] = 'LR'
  g[:tooltip] = ' '

  # Add nodes for each thing
  types = [[:playbook, {:shape => 'folder', :fillcolor => 'cornflowerblue'}],
           [:role, {:shape => 'house', :fillcolor => 'palegreen'}],
           [:task, {:shape => 'oval', :fillcolor => 'white'}],
           [:var, {:shape => 'octagon', :fillcolor => 'cornsilk'}]]
  types.each {|type, attrs|
    dict[type].each_pair {|name, it|
      node = g.get_or_make(name)
      node[:style] = 'filled'
      it[:node] = node
      attrs.each_pair {|k,v| node[k] = v }
      if it[:label]
        node[:label] = it[:label]
        node[:tooltip] = it[:name]
      else
        node[:tooltip] = type.to_s.capitalize
      end
    }
  }

  # Add edges from playbooks to roles and tasks
  dict[:playbook].each_value {|playbook|
    (playbook[:roles] || []).each {|role|
      g.add GEdge[playbook[:node], role[:node],
        {:tooltip => "includes"}]
    }
    (playbook[:tasks] || []).each {|task|
      g.add GEdge[playbook[:node], task[:node],
        {:style => 'dashed', :color => 'blue',
         :tooltip => "calls task"}]
    }
  }

  # Add edges from roles to other things
  dict[:role].each_value {|role|
    (role[:role_deps] || []).each {|dep|
      g.add GEdge[role[:node], dep[:node],
        {:color => 'hotpink',
         :tooltip => "calls foreign task"}]
    }

    (role[:tasks] || []).each {|task|
      g.add GEdge[role[:node], task[:node],
        {:tooltip => "calls task"}]
    }

    (role[:vars] || []).each {|var|
      g.add GEdge[role[:node], var[:node],
        {:tooltip => "provides var"}]
    }
  }

  # Add edges from tasks to vars
  dict[:task].each_value {|task|
    if task[:node] == nil
      next
    end
    (task[:used_vars] || []).each {|var|
      g.add GEdge[task[:node], var[:node],
        {:style => 'dotted',
         :tooltip => "uses var"}]
    }
    }

  hide_tasks = dict[:task].each_value.find_all {|it|
    it[:label] =~ /^_|^main$/
  }.map {|it| it[:node] }
  g.lowercut(*hide_tasks)

  g = decorate(g, dict, options)

  if not options.show_vars
    g.cut(*(dict[:var].values.map {|it| it[:node] }))
  end

  g
end


########## DECORATE ###########

# This is accessed as a global from graph_viz.rb, EWW
def rank_node(node)
  case node[:shape]
  when /folder/ then :source
  when /oval/ then :same
  when /octagon/ then :sink
  end
end

def decorate(g, dict, options)
  decorate_nodes(g, dict, options)

  dict[:role].values.map {|r| r[:node] }.each {|n|
    if n.inc_nodes.empty?
      n[:fillcolor] = 'yellowgreen'
      n[:tooltip] = 'not used by any playbook'
    end
  }

#    dict[:role].values.each {|r|
#      r[:node][:tooltip] = r[:unused_vars].map {|v| v[:label] }.join(" ")
#    }
  dict[:role].values.flat_map {|r| r[:unused_vars] }.
      map {|v| v[:node] }.
      each {|n|
    n[:fillcolor] = 'yellow'
    n[:tooltip] += '. (EXPERIMENTAL) appears not to be used by any task in the owning role'
  }

  dict[:role].values.flat_map {|r| r[:undefed_vars] }.compact. # FIXME compact
      map {|v| v[:node] }.
      each {|n|
    n[:fillcolor] = 'red'
    n[:tooltip] += '. (EXPERIMENTAL) not defined by this role;' +
                  ' could be included from another role or not really a var'
  }

  g
end

def decorate_nodes(g, dict, options)
end

########## RENDER #############

def write(graph, filename)
  Mustache.template_file = 'diagram.mustache'
  view = Mustache.new
  view[:now] = Time.now.strftime("%Y.%m.%d %H:%M:%S")

  view[:title] = "Ansible dependencies"
  view[:dotdata] = g2dot(graph)

  path = filename
  File.open(path, 'w') do |f|
    f.puts view.render
  end
end


########## OPTIONS #############

options = OpenStruct.new
options.format = :hot
options.output_filename = "viz.html"
options.show_vars = false
OptionParser.new do |o|
  o.banner = "Usage: ansible-viz.rb [options] <path-to-playbooks>"
  o.on("-o", "--output [FILE]", "Where to write output") do |fname|
    options.output_filename = fname
  end
  o.on("--vars",
       "Include vars. WARNING: unused/undefined support is EXPERIMENTAL.") do |val|
    options.show_vars = true
  end
  o.on_tail("-h", "--help", "Show this message") do
    puts o
    exit
  end
end.parse!
if ARGV.length != 1
  abort("Must provide the path to your playbooks")
end
options.playbook_dir = ARGV.shift

dict = load_data(options)
graph = graphify(dict, options)
write(graph, options.output_filename)
