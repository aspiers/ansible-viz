#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require './graphviz'
require 'fileutils'
require 'ostruct'
require 'pp'


class Grapher
  def graph(dict, options)
    # FIXME Cosmetic stuff should be in decorate_* methods

    g = Graph.new
    g[:rankdir] = 'LR'
    g[:tooltip] = ' '

    add_nodes(g, dict)
    connect_playbooks(g, dict)
    connect_roles(g, dict)
#    hide_dull_tasks(g, dict)

    decorate(g, dict, options)

    if not options.show_vars
#      g.cut(*(dict[:var].values.map {|it| it[:node] }))
    end

    g
  end

  def add_nodes(g, dict)
    dict[:role].each_pair {|name, role|
      add_node(g, name, role)
      role[:task].each_pair {|n, task| add_node(g, n, task) }
      role[:var].each_pair {|n, var| add_node(g, n, var) }
    }
    dict[:playbook].each_pair {|name, playbook|
      add_node(g, name, playbook)
      playbook[:role].each {|role| add_node(g, role[:name], role) }
      playbook[:task].each {|task| add_node(g, task[:name], task) }
    }
  end

  def add_node(g, name, it)
      node = g.get_or_make(name)
      node.data = it
      it[:node] = node
  end

  def connect_playbooks(g, dict)
    dict[:playbook].each_value {|playbook|
      (playbook[:role] || []).each {|role|
        g.add GEdge[playbook[:node], role[:node],
          {:tooltip => "includes"}]
      }
      (playbook[:task] || []).each {|task|
        g.add GEdge[playbook[:node], task[:node],
          {:style => 'dashed', :color => 'blue',
           :tooltip => "calls task"}]
      }
    }
  end

  def connect_roles(g, dict)
    dict[:role].each_value {|role|
      (role[:role_deps] || []).each {|dep|
        g.add GEdge[role[:node], dep[:node],
          {:color => 'hotpink',
           :tooltip => "calls foreign task"}]
      }

      (role[:task] || []).each_value {|task|
        g.add GEdge[role[:node], task[:node],
          {:tooltip => "calls task"}]

#        (task[:used_vars] || []).each {|var|
#          g.add GEdge[task[:node], var[:node],
#            {:style => 'dotted',
#             :tooltip => "uses var"}]
#        }
      }

      (role[:var] || []).each_value {|var|
        g.add GEdge[role[:node], var[:node],
          {:tooltip => "provides var"}]
      }
    }
  end

  def hide_dull_tasks(g, dict)
    hide_tasks = dict[:task].each_value.find_all {|it|
      it[:label] =~ /^_|^main$/
    }.map {|it| it[:node] }
    g.lowercut(*hide_tasks)
  end


  ########## DECORATE ###########

  def decorate(g, dict, options)
    decorate_nodes(g, dict, options)

    dict[:role].values.map {|r| r[:node] }.each {|node|
      if node.inc_nodes.empty?
        node[:fillcolor] = 'yellowgreen'
        node[:tooltip] = 'not used by any playbook'
      end
    }

  #    dict[:role].values.each {|r|
  #      r[:node][:tooltip] = r[:unused_vars].map {|v| v[:label] }.join(" ")
  #    }
    dict[:role].values.flat_map {|r| r[:unused_vars] }.
        map {|v| v[:node] }.
        each {|node|
      node[:fillcolor] = 'yellow'
      node[:tooltip] += '. (EXPERIMENTAL) appears not to be used by any task in the owning role'
    }

#    dict[:role].values.flat_map {|r| r[:undefed_vars] }.compact. # FIXME compact
#        map {|v| v[:node] }.
#        each {|node|
#      node[:fillcolor] = 'red'
#      node[:tooltip] += '. (EXPERIMENTAL) not defined by this role;' +
#                    ' could be included from another role or not really a var'
#    }
  end

  def decorate_nodes(g, dict, options)
    types = {:playbook => {:shape => 'folder', :fillcolor => 'cornflowerblue'},
             :role => {:shape => 'house', :fillcolor => 'palegreen'},
             :task => {:shape => 'oval', :fillcolor => 'white'},
             :var => {:shape => 'octagon', :fillcolor => 'cornsilk'}}
    g.nodes.each {|node|
      type = node.data[:type]
      types[type].each_pair {|k,v| node[k] = v }
      node[:style] = 'filled'
      node[:tooltip] = type.to_s.capitalize
#      case type
#      when :task
#        node[:label] = it[:label]
#      when :var
#      end
#      if it[:label]
#        node[:label] = it[:label]
#        node[:tooltip] = it[:name]
#      else
#      end
    }
  end
end

# This is accessed as a global from graph_viz.rb, EWW
def rank_node(node)
  case node[:shape]
  when /folder/ then :source
  when /oval/ then :same
  when /octagon/ then :sink
  end
end
