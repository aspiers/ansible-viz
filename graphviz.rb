#!/usr/bin/ruby
# vim: set ts=2 sw=2:

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

  def initialize(key, attrs = {})
    @key = key
    @attrs = attrs
    self[:label] = key
    @node = "n#@@node_counter"
    @@node_counter += 1

    @inc = Set[]
    @out = Set[]
  end

  def initialize_copy(src)
    super
    @inc = Set[]
    @out = Set[]
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
  end

  attr_accessor :nodes, :edges, :attrs

  def initialize(nodes = [], edges = [], attrs = {})
    @nodes = Set[*nodes]
    @edges = Set[]
    add(*edges)
    @attrs = attrs
  end

  def initialize_copy(src)
    super
    @nodes = @nodes.map {|i| i.dup }.to_set
    @edges = Set[]
    src.edges.each {|i|
      add GEdge[get(i.snode.key), get(i.dnode.key), i.attrs.dup]
    }
    @attrs = @attrs.dup
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

  def match(*pats)
    Set.new(@nodes).keep_if {|n|
      pats.any? {|p| n.label =~ p }
    }
  end

  def match_src(*pats)
    Set.new(@edges).keep_if {|e|
      pats.any? {|p| e.src =~ p }
    }
  end
  def match_dst(*pats)
    Set.new(@edges).keep_if {|e|
      pats.any? {|p| e.dst =~ p }
    }
  end

  def add(*items)
    items.each {|i|
      case i
      when GNode
        # puts "N+++: #{i.inspect}"
        @nodes.add i
      when GEdge
        # puts "E+++: #{i.inspect}"
        @nodes.add i.snode
        @nodes.add i.dnode
        @edges.add i
        i.snode.out.add i
        i.dnode.inc.add i
        # puts "E---: #{i.inspect}"
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
      else raise "Unexpected item: #{i.inspect}"
      end
    }
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
    keep_nodes = Set[]
    keep_edges = Set[]
    to_walk = Array.new(nodes)
    while !to_walk.empty?
      item = to_walk.pop
      keep_nodes << item
      keep_edges += item.inc
      to_walk += item.inc_nodes - keep_nodes.to_a
    end
    to_walk = Array.new(nodes)
    while !to_walk.empty?
      item = to_walk.pop
      keep_nodes << item
      keep_edges += item.out
      to_walk += item.out_nodes - keep_nodes.to_a
    end
    Graph.new(keep_nodes, keep_edges, @attrs)
  end

  def inspect
    [(Graph.include_hashes and "Hash: ##{hash}" or nil),
     "Nodes:",
     @nodes.map {|n| "  "+ n.inspect },
     "Edges:",
     @edges.map {|e| "  "+ e.inspect }].
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

def g2dot(graph)
  dot_ranks = graph.nodes.
    # TODO pass rank_node in somehow
    classify {|v| rank_node(v) }.
    map {|k,v|
      nl = "\n  "
      nl += "  " if k != nil

      rnodes = v.map {|n|
        nl + n.node + wrapattrs(n.attrs) +";"
      }.join("")

      case k
      when nil then rnodes
      when :source, :min, :max, :sink
        "{ rank = #{k};#{rnodes} }"
      else
        "{ rank = same;#{rnodes} }"
      end
    }.join("\n  ")

  dot_edges = graph.edges.map {|e|
    "#{e.snode.node} -> #{e.dnode.node}#{wrapattrs(e.attrs)};"
  }.join("\n  ")

  <<-EOT
digraph G {
  #{joinattrs(graph.attrs).join("\n  ")}
  #{dot_ranks}
  #{dot_edges}
}
  EOT
end
