#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require './graphviz'
require './styler'
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

    if not options.show_vars
      to_cut = g.nodes.find_all {|n| n.data[:type] == :var }
      g.cut(*to_cut)
    end

    g
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
    if src[:node] == nil
      raise "Bad src: #{src[:name]}"
    elsif dst[:node] == nil
      raise "Bad dst: #{dst[:name]}"
    end
    edge = GEdge[src[:node], dst[:node], {:tooltip => tooltip}.merge(extra)]
    g.add edge
    edge
  end

  def connect_playbooks(g, dict, styler)
    dict[:playbook].each {|playbook|
      (playbook[:include] || []).each {|pb|
        edge = add_edge(g, playbook, pb, "includes")
        styler.style(edge, :include_playbook)
      }
      (playbook[:role] || []).each {|role|
        add_edge(g, playbook, role, "includes")
      }
      (playbook[:task] || []).each {|task|
        edge = add_edge(g, playbook, task, "calls task")
        styler.style(edge, :call_task)
      }
    }
  end

  def connect_roles(g, dict, styler)
    dict[:role].each {|role|
      (role[:role_deps] || []).each {|dep|
        edge = add_edge(g, role, dep, "includes role")
        styler.style(edge, :includes_role)
      }

      role[:task].each {|task|
        connect_task(g, dict, task, styler)
      }

      (role[:varfile] || []).each {|vf|
        add_edge(g, role, vf, "defines var")
        vf[:var].each {|v|
          add_edge(g, vf, v, "defines var")
        }
      }

      (role[:vardefaults] || []).each {|vf|
        add_edge(g, role, vf, "defines defaults")
        vf[:var].each {|v|
          add_edge(g, vf, v, "defines default var")
        }
      }

      (role[:template] || []).each {|tm|
        add_edge(g, role, tm, "provides template")
      }
    }
  end

  def connect_task(g, dict, task, styler)
    add_edge(g, task[:parent], task, "calls")

    task[:var].each {|var|
      if var[:defined]
        add_edge(g, task, var, "sets fact")
      end
    }

    task[:included_tasks].each {|incl_task|
      privet = (task[:parent] != incl_task[:parent] and incl_task[:name][0] == '_')
      style = if privet then :private else :includes_task end
      styler.style(add_edge(g, task, incl_task, "includes task"), style)
    }

    task[:used_templates].each {|tm|
      styler.style(add_edge(g, task, tm, "applies template"), :applies_template)
    }
  end

  def connect_usage(g, dict, styler)
    dict[:role].each {|role|
      [:task, :varfile, :vardefaults, :template].
        flat_map {|sym| role[sym] }.
        each {|thing|
          (thing[:uses] || []).each {|var|
            edge = add_edge(g, thing, var, "uses var")
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
