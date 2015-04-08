#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'set'

########## MODELLING ##########

class GNode
  class <<self
    def [](k,a={}); self.new(k,a); end
  end

  @@node_counter = 0
  attr_accessor :key, :node, :attrs
  attr_accessor :inc, :out
  attr_accessor :rank
  # Somewhere to link data, to help decoration
  attr_accessor :data

  def initialize(key, attrs = {})
    @key = key
    @attrs = {}
    self[:label] = key
    @attrs.merge! attrs
    @node = "n#@@node_counter"
    @@node_counter += 1

    @inc = []
    @out = []
  end

  def initialize_copy(src)
    super
    @inc = []
    @out = []
  end

  def label; self[:label]; end
  def label=(v); self[:label] = v; end
  def inc_nodes; @inc.map {|i| i.snode }; end
  def out_nodes; @out.map {|i| i.dnode }; end

  def [](k); attrs[k]; end
  def []=(k, v); attrs[k] = v; end

  def inspect
    hsh = (Graph.include_hashes and " ##{hash}" or "")
    "N[#@key#{hsh} #{inc.count}/#{out.count}]"
  end
end


class GEdge
  class <<self
    def [](s,d,a={}); self.new(s,d,a); end
  end

  attr_accessor :snode, :dnode, :attrs

  def initialize(snode, dnode, attrs = {})
    @snode, @dnode = snode, dnode
    @attrs = attrs
  end

  def initialize_copy(src)
    raise "Don't dup edges"
  end

  def ==(o)
    snode == o.snode and dnode == o.dnode
  end

  def src; @snode.label; end
  def dst; @dnode.label; end

  def [](k); attrs[k]; end
  def []=(k, v); attrs[k] = v; end

  def inspect
    hsh = (Graph.include_hashes and ", ##{hash}" or "")
    "E[#{snode.inspect} -> #{dnode.inspect}#{hsh}]"
  end
end


class Graph
  class <<self
    def include_hashes
      false
    end

    def from_hash(hash)
      g = Graph.new
      hash.each_key {|k|
        g.add GNode[k]
      }
      hash.each_pair {|k, run_list|
        src = g.get(k)
        run_list.each_with_index { |i,ix|
          dst = g.get(i)
          if dst == nil
            dst = GNode[i]
            g.add dst
          end
          g.add GEdge[src, dst, {
                      :taillabel => ix + 1,
                      :labeldistance => 2.0 }]
        }
      }
      g
    end

    def new_subgraph(name)
      g = Graph.new
      g.name = name
      g
    end
    def new_cluster(name)
      g = Graph.new
      g.name = name
      g.is_cluster = true
      g
    end
  end

  @@cluster_counter = 0
  attr_accessor :nodes, :edges, :subgraphs, :attrs
  attr_accessor :is_cluster, :name
  attr_accessor :rank_fn

  def initialize(nodes = [], edges = [], attrs = {})
    @nodes = nodes.dup
    @edges = []
    add(*edges)
    @attrs = attrs
    @subgraphs = []
    @is_cluster = false
    @name = 'Graph'
    @rank_fn = Proc.new {|node| nil }
  end

  def initialize_copy(src)
    @nodes = @nodes.map {|i| i.dup }.to_set
    @edges = []
    src.edges.each {|i|
      add GEdge[get(i.snode.key), get(i.dnode.key), i.attrs.dup]
    }
    @attrs = @attrs.dup
    @subgraphs = @subgraphs.map {|sg| Graph.new.initialize_copy(sg) }
  end

  def [](k); attrs[k]; end
  def []=(k, v); attrs[k] = v; end

  def get(k1, k2=nil)
    case k2
    when nil
      @nodes.each {|n|
        return n if n.key == k1
      }
    else
      @edges.each {|e|
        return n if n.snode.key == k1 and n.dnode.key == k2
      }
    end
    nil
  end
  def get_or_make(k)
    n = get(k)
    if n == nil
      n = GNode[k]
      add n
    end
    n
  end

  def add(*items)
    items.each {|i|
      case i
      when GNode
        # puts "N+++: #{i.inspect}"
        @nodes.push i
      when GEdge
        # puts "E+++: #{i.inspect}"
        @nodes.push i.snode
        @nodes.push i.dnode
        @edges.push i
        i.snode.out.push i
        i.dnode.inc.push i
        # puts "E---: #{i.inspect}"
      when Graph
        @subgraphs.unshift i
      else raise "Unexpected item: #{i.inspect}"
      end
    }
  end

  def cut(*items)
    items.each {|i|
      case i
      when GNode
        @nodes.delete i
        cut(*(i.out + i.inc))
      when GEdge
        @edges.delete i
        i.snode.out.delete i
        i.dnode.inc.delete i
      when Graph
        @subgraphs.delete i
      else raise "Unexpected item: #{i.inspect}"
      end
    }
    @subgraphs.each {|sg| sg.cut(*items) }
  end

  def lowercut(*items)
    items.each {|i|
      # puts "cut: #{i.inspect}"
      case i
      when GNode
        @nodes.delete i
        lowercut(*(i.out + i.inc))
      when GEdge
        cut i
        if i.dnode.inc.empty?
          lowercut i.dnode
        end
      else raise "Unexpected item: #{i.inspect}"
      end
    }
  end

  def focus(*nodes)
    # TODO: make new nodes + edges
    keep_nodes = []
    keep_edges = []
    to_walk = Array.new(nodes)
    while !to_walk.empty?
      item = to_walk.pop
      keep_nodes << item
      keep_edges += item.inc
      to_walk += item.inc_nodes - keep_nodes
    end
    to_walk = Array.new(nodes)
    while !to_walk.empty?
      item = to_walk.pop
      keep_nodes << item
      keep_edges += item.out
      to_walk += item.out_nodes - keep_nodes
    end
    Graph.new(keep_nodes, keep_edges, @attrs)
  end

  def rank_nodes
    Set[*@nodes].classify {|n| @rank_fn.call(n) }
  end

  def inspect
    [(Graph.include_hashes and "Hash: ##{hash}" or nil),
     "Nodes:",
     @nodes.map {|n| "  "+ n.inspect },
     "Edges:",
     @edges.map {|e| "  "+ e.inspect },
     "Subgraphs:",
     @subgraphs.map {|sg|
       sg.inspect.split($/).map {|line| "  "+ line }
     }].
      compact.
      join("\n")
  end
end

########## GENERATE DOT #############

def joinattrs(h)
  h.select {|k,v| v != nil }.
    map {|k,v| "#{k}=\"#{v}\""}
end
def wrapattrs(h)
  a = joinattrs(h).join(", ")
  a.length > 0 and " [#{a}]" or ""
end

def g2dot(graph, level=0)
  gtype = ((level > 0 and "subgraph") or "digraph")
  gname = ((graph.is_cluster and "cluster#{graph.name}") or graph.name)

  # Subgraphs go first so they don't inherit attributes
  body = []
  body += graph.subgraphs.flat_map {|sg| g2dot(sg, level + 1).split("\n") }
  body += joinattrs(graph.attrs)

  body += graph.rank_nodes.
      flat_map {|k,v|
        rnodes = v.map {|n|
          n.node + wrapattrs(n.attrs) +";"
        }
        tab_rnodes = rnodes.map {|line| "  " + line }

        case k
        when nil then rnodes
        when :source, :min, :max, :sink
          ["{ rank = #{k};", *tab_rnodes, "}"]
        when :same
          raise "Don't use 'same' rank directly"
        else
          ["{ rank = same;", *tab_rnodes, "}"]
        end
      }
  body += graph.edges.map {|e|
    "#{e.snode.node} -> #{e.dnode.node}#{wrapattrs(e.attrs)};"
  }

  body.map! {|line| "  " + line }
  ["#{gtype} \"#{gname}\" {", *body, "}"].
    map {|line| line + "\n" }.join("")
end
