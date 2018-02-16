#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'ansible_viz/graphviz'
require 'ansible_viz/styler'
require 'pp'


class Grapher
  def graph(dict, options)
    g = Graph.new
    g[:tooltip] = ' '
    g[:label] = "Ansible dependencies"
    g[:fontsize] = 36
    g.rank_fn = Proc.new {|node| rank_node(node) }

    styler = Styler.new
    add_nodes(g, dict, styler, options.show_usage)
    connect_playbooks(g, dict, styler)
    connect_roles(g, dict, styler)
    if options.show_usage
      connect_usage(g, dict, styler)
    end

    styler.decorate(g, dict, options)

    cut(g, options)

    g
  end

  def cut(g, options)
    %w(var varfile vardefaults template task).each do |type|
      option = "show_%ss" % type.gsub(/s$/, '')
      if not options.send option
        to_cut = g.nodes.find_all {|n| n.data[:type] == type.to_sym }
        g.cut(*to_cut)
      end
    end

    if options.exclude_nodes
      exclude_nodes = g.nodes.find_all {|n|
        descriptor = "%s:%s" % [n.data[:type], n.data[:fqn]]
        exclude = descriptor =~ options.exclude_nodes
        if exclude
          puts "Excluding node #{descriptor}"
        end
        exclude
      }
      g.cut(*exclude_nodes)
    end

    if options.exclude_edges
      exclude_edges = g.edges.find_all {|e|
        descriptor = "%s:%s -> %s:%s" % [
          e.snode.data[:type], e.snode.data[:fqn],
          e.dnode.data[:type], e.dnode.data[:fqn]
        ]
        exclude = descriptor =~ options.exclude_edges
        if exclude
          puts "Excluding edge #{descriptor}"
        end
        exclude
      }
      g.cut(*exclude_edges)
    end
  end

  def rank_node(node)
      return nil
  end

  def add_node(g, it)
    node = GNode[it[:fqn]]
    node.data = it
    it[:node] = node
    g.add(node)
  end

  def add_nodes(g, dict, styler, show_usage)
    vars = []
    dict[:role].each {|role|
      add_node(g, role)
      role[:task].each {|task|
        add_node(g, task)
        vars += task[:var]
      }
      (role[:varfile] + role[:vardefaults]).each {|vf|
        add_node(g, vf)
        vars += vf[:var]
      }
      role[:template].each {|tm|
        add_node(g, tm)
      }
    }
    vars.each {|v|
      if show_usage or v[:defined]
        add_node(g, v)
      end
    }
    dict[:playbook].each {|playbook|
      add_node(g, playbook)
      # Roles and tasks should already have nodes
    }
  end

  def add_edge(g, src, dst, tooltip, extra={})
    raise "Nil src for edge, tooltip: #{tooltip}" if src.nil?
    raise "Bad src: #{src[:name]}" if src[:node].nil?

    raise "Nil dst for edge, tooltip: #{tooltip}" if dst.nil?
    raise "Bad dst: #{dst[:name]}" if dst[:node].nil?

    edge = GEdge[src[:node], dst[:node], {:tooltip => tooltip}.merge(extra)]
    g.add edge
    edge
  end

  def connect_playbooks(g, dict, styler)
    dict[:playbook].each {|playbook|
      (playbook[:include] || []).each {|pb|
        edge = add_edge(g, playbook, pb,
                        "#{playbook[:fqn]} includes playbook #{pb[:fqn]}")
        styler.style(edge, :include_playbook)
      }
      (playbook[:role] || []).each {|role|
        add_edge(g, playbook, role,
                 "#{playbook[:fqn]} invokes role #{role[:name]}")
      }
      (playbook[:task] || []).each {|task|
        edge = add_edge(g, playbook, task,
                        "#{playbook[:fqn]} calls task #{task[:fqn]}")
        styler.style(edge, :call_task)
      }
    }
  end

  def connect_roles(g, dict, styler)
    dict[:role].each {|role|
      (role[:role_deps] || []).each {|dep|
        edge = add_edge(g, role, dep, "#{role[:fqn]} includes role #{dep[:fqn]}")
        styler.style(edge, :includes_role)
      }

      role[:task].each {|task|
        connect_task(g, dict, task, styler)
      }

      (role[:varfile] || []).each {|vf|
        add_edge(g, role, vf, "#{role[:fqn]} uses varfile #{vf[:fqn]}")
        vf[:var].each {|v|
          add_edge(g, vf, v, "#{vf[:fqn]} defines var #{v[:fqn]}")
        }
      }

      (role[:vardefaults] || []).each {|vf|
        add_edge(g, role, vf, "#{role[:fqn]} uses default varfile #{vf[:fqn]}")
        vf[:var].each {|v|
          add_edge(g, vf, v, "#{vf[:fqn]} defines var #{v[:fqn]}")
        }
      }

      (role[:template] || []).each {|tm|
        add_edge(g, role, tm, "#{role[:fqn]} provides template #{tm[:fqn]}")
      }
    }
  end

  def connect_task(g, dict, task, styler)
    add_edge(g, task[:parent], task,
             "#{task[:parent][:fqn]} calls #{task[:fqn]}")

    task[:var].each {|var|
      if var[:defined]
        add_edge(g, task, var, "#{task[:fqn]} sets fact #{var[:fqn]}")
      end
    }

    task[:included_tasks].each {|incl_task|
      privet = (task[:parent] != incl_task[:parent] and incl_task[:name][0] == '_')
      style = if privet then :private else :includes_task end
      styler.style(add_edge(g, task, incl_task,
                            "#{task[:fqn]} includes task #{incl_task[:fqn]}"), style)
    }

    task[:used_templates].each {|tm|
      styler.style(add_edge(g, task, tm,
                            "#{task[:fqn]} applies template #{tm[:fqn]}"),
                   :applies_template)
    }
  end

  def connect_usage(g, dict, styler)
    dict[:role].each {|role|
      [:task, :varfile, :vardefaults, :template].
        flat_map {|sym| role[sym] }.
        each {|thing|
          (thing[:uses] || []).each {|var|
            edge = add_edge(g, thing, var,
                            "#{thing[:fqn]} uses var #{var[:fqn]}")
            styler.style(edge, :use_var)
          }
        }
    }
  end

  # This helps prevent unlinked nodes distorting the graph when it's all messed up.
  # Normally there shouldn't be (m)any unlinked nodes.
  def extract_unlinked(g)
    spare = g.nodes.find_all {|n|
      (n.inc_nodes + n.out_nodes).length == 0
    }
    g.cut(*spare)

    unlinked = Graph.new_cluster('unlinked')
    unlinked.add(*spare)
    unlinked[:bgcolor] = Styler.hsl(15, 0, 97)
    unlinked[:label] = "Unlinked nodes"
    unlinked[:fontsize] = 36
    unlinked.rank_fn = Proc.new {|node| node.data[:type] }
    unlinked
  end
end
