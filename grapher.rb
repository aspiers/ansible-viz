#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require './graphviz'
require 'fileutils'
require 'ostruct'
require 'pp'


class Grapher
  def graph(dict, options)
    g = Graph.new
    g[:rankdir] = 'LR'
    g[:tooltip] = ' '

    add_nodes(g, dict)
    connect_playbooks(g, dict)
    connect_roles(g, dict)

    decorate(g, dict, options)

    hide_dullness(g, dict)

    if not options.show_vars
      to_cut = g.nodes.find_all {|n| n.data[:type] == :var }
      g.cut(*to_cut)
    end

    g
  end

  def collect_parents(it)
    case it[:type]
    when :playbook, :role
      return [it]
    end
    if it[:parent] == nil
      pp it
    end
    collect_parents(it[:parent]) + [it]
  end

  def add_node(g, it)
    fqn = collect_parents(it)
    fqn = fqn.map {|i| i[:name] }.join("::")
    node = GNode[fqn]
    node.data = it
    it[:node] = node
    g.add(node)
  end

  def add_nodes(g, dict)
    dict[:role].each {|role|
      add_node(g, role)
      role[:task].each {|task|
        add_node(g, task)
        task[:var].each {|var| add_node(g, var) }
      }
      role[:varset].each {|vs|
        add_node(g, vs)
        vs[:var].each {|v| add_node(g, v) }
      }
    }
    dict[:playbook].each {|playbook|
      add_node(g, playbook)
      # Roles and tasks should already have nodes
    }
  end

  def add_edge(g, src, dst, tooltip, extra={})
    if src[:node] == nil
      raise "Bad src: #{src[:name]}"
    elsif dst[:node] == nil
      raise "Bad dst: #{dst[:name]}"
    end
    g.add GEdge[src[:node], dst[:node], {:tooltip => tooltip}.merge(extra)]
  end

  def connect_playbooks(g, dict)
    dict[:playbook].each {|playbook|
      (playbook[:role] || []).each {|role|
        add_edge(g, playbook, role, "includes")
      }
      (playbook[:task] || []).each {|task|
        add_edge(g, playbook, task, "calls task",
          {:style => 'dashed', :color => 'blue'})
      }
    }
  end

  def connect_roles(g, dict)
    dict[:role].each {|role|
      (role[:role_deps] || []).each {|dep|
        add_edge(g, role, dep, "calls foreign task",
          {:color => 'red'})
      }

      role[:task].each {|task|
        add_edge(g, role, task, "calls task")
        task[:var].each {|var|
          add_edge(g, task, var, "sets fact")
        }

#        (task[:used_vars] || []).each {|var|
#          add_edge(g, task, var, "uses var",
#            {:style => 'dotted'})
#        }
      }

      (role[:varset] || []).each {|vs|
        is_main = false  #vs[:name] == 'main'
        add_edge(g, role, vs, "defines var") unless is_main
        vs[:var].each {|v|
          add_edge(g, (is_main and role or vs), v, "defines var")
        }
      }
    }
  end

  def hide_dullness(g, dict)
    # Given a>main>c, produce a>c
    g.nodes.find_all {|n|
      n.data[:name] == 'main' or n.data[:type] == :vardefaults
    }.each {|n|
      inc_node = n.inc_nodes[0]
      n.out.each {|e| e.snode = inc_node }
      n.out = Set[]
      g.cut n
    }

#    dict[:role].each {|r|
#      hide_tasks = r[:task].each.find_all {|it|
#        it[:name] =~ /^_/
#      }.map {|it| it[:node] }
#      g.lowercut(*hide_tasks)
#    }
  end


  ########## DECORATE ###########

  def decorate(g, dict, options)
    decorate_nodes(g, dict, options)

    dict[:role].each {|role|
      if role[:node].inc_nodes.empty?
        role[:node][:fillcolor] = 'yellowgreen'
        role[:node][:tooltip] = 'not used by any playbook'
      end
    }

    # FIXME
#    dict[:role].each {|r|
#      r[:var].each {|v|
#        if not v[:used]
#          v[:node][:fillcolor] = 'yellow'
#          v[:node][:tooltip] += '. (EXPERIMENTAL) appears not to be used by any task in the owning role'
#        elsif not v[:defined]
#          v[:node][:fillcolor] = 'red'
#          v[:node][:tooltip] += '. (EXPERIMENTAL) not defined by this role;' +
#                            ' could be included from another role or not really a var'
#        end
#      }
#    }
  end

  def hsl(h, s, l)
    [h, s, l].map {|i| i / 100.0 }.join("+")
  end

  def decorate_nodes(g, dict, options)
    types = {:playbook => {:shape => 'folder', :fillcolor => hsl(66, 8, 100)},
             :role => {:shape => 'house', :fillcolor => hsl(66, 24, 100)},
             :task => {:shape => 'octagon', :fillcolor => hsl(66, 40, 100)},
             :varset => {:shape => 'box3d', :fillcolor => hsl(33, 8, 100)},
             :var => {:shape => 'oval', :fillcolor => hsl(33, 60, 80)}}
    g.nodes.each {|node|
      data = node.data
      type = data[:type]
      type = :varset if type == :vardefaults
      types[type].each_pair {|k,v| node[k] = v }
      node[:label] = data[:name]
      node[:style] = 'filled'
      fqn = collect_parents(data)
      fqn = fqn.map {|i| i[:name] }.join("::")
      node[:tooltip] = "#{type.to_s.capitalize} #{fqn}"

      case type
      when :var
        if node.inc_nodes.all? {|n| n.data[:type] == :task }
          node[:fillcolor] = hsl(33, 70, 100)
        elsif node.inc_nodes.all? {|n| n.data[:type] == :vardefaults }
          node[:fillcolor] = hsl(33, 90, 60)
          node[:fontcolor] = hsl(0, 0, 100)
        end
        if not data[:used]
          node[:fillcolor] = hsl(88, 50, 100)
        elsif not data[:defined]
          node[:fillcolor] = hsl(88, 100, 100)
        end
      end
    }
  end
end

# This is accessed as a global from graph_viz.rb, EWW
def rank_node(node)
  case node.data[:type]
  when :playbook then :source
  when :task, :varset then :same
  when :var then :sink
  end
end
