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
end

# This is accessed as a global from graph_viz.rb, EWW
def rank_node(node)
  case node[:shape]
  when /folder/ then :source
  when /oval/ then :same
  when /octagon/ then :sink
  end
end
