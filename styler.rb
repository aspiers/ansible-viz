#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require './graphviz'
require 'pp'


class Styler
  class <<self
    def hsl(h, s, l)
      [h, s, l].map {|i| i / 100.0 }.join("+")
    end
  end

  @@style = {
    # Node styles
    :playbook => {
      :shape => 'folder',
      :style => 'filled',
      :fillcolor => hsl(13, 40, 100)},
    :role => {
      :shape => 'house',
      :style => 'filled',
      :fillcolor => hsl(66, 24, 100)},
    :task => {
      :shape => 'octagon',
      :style => 'filled',
      :fillcolor => hsl(66, 40, 100)},
    :varfile => {
      :shape => 'box3d',
      :style => 'filled',
      :fillcolor => hsl(33, 8, 100)},
    :vardefaults => {
      :shape => 'box3d',
      :style => 'filled',
      :fillcolor => hsl(33, 8, 90)},
    :var => {
      :shape => 'oval',
      :style => 'filled',
      :fillcolor => hsl(33, 60, 80)},

    # Node decorations
    :role_unused   => {:style => 'filled',
                       :fillcolor => hsl(82, 24, 100)},
    :var_unused    => {:style => 'filled',
                       :fillcolor => hsl(88, 50, 100),
                       :fontcolor => hsl(0, 0, 0)},
    :var_undefined => {:style => 'filled',
                       :fillcolor => hsl(88, 100, 100)},
    :var_default   => {:style => 'filled',
                       :fillcolor => hsl(33, 90, 60),
                       :fontcolor => hsl(0, 0, 100)},
    :var_fact      => {:style => 'filled',
                       :fillcolor => hsl(33, 70, 100)},

    # Edge styles
    :use_var => {:color => hsl(0, 0, 85),
                 :tooltip => 'uses var'},
    :call_task => {:color => 'blue', :penwidth => 2, :style => 'dashed'},
    :include_playbook => {:color => hsl(33, 100, 40), :penwidth => 2, :style => 'dashed'},
    :includes_role => {:color => hsl(33, 100, 40), :penwidth => 2, :style => 'dashed'},
    :includes_task => {:color => hsl(33, 100, 40), :penwidth => 2, :style => 'dashed'},
    :private => {:color => 'red', :penwidth => 2, :style => 'dashed'},
    :call_extra_task => {:color => 'red', :penwidth => 2},
  }

  def style(node_or_edge, style)
    while style.is_a?(Symbol)
      style = @@style[style] || {}
    end
    style.each_pair {|k,v| node_or_edge[k] = v }
    node_or_edge
  end

  def decorate(g, dict, options)
    decorate_nodes(g, dict, options)

    dict[:role].each {|role|
      if role[:node].inc_nodes.empty?
        style(role[:node], :role_unused)
        role[:node][:tooltip] += '. Unused by any playbook'
      end
    }
  end

  def decorate_nodes(g, dict, options)
    g.nodes.each {|node|
      data = node.data
      type = data[:type]
      style(node, type)
      node[:label] = data[:name]
      typename = case type
                 when :varfile then "Vars"
                 else type.to_s.capitalize
                 end
      node[:tooltip] = "#{typename} #{data[:fqn]}"

      case type
      when :var
        if data[:used].length == 0
          style(node, :var_unused)
          node[:tooltip] += '. UNUSED.'
        elsif not data[:defined]
          style(node, :var_undefined)
          node[:tooltip] += '. UNDEFINED.'
        elsif node.inc_nodes.all? {|n| n.data[:type] == :vardefaults }
          style(node, :var_default)
        elsif node.inc_nodes.all? {|n| n.data[:type] == :task }
          style(node, :var_fact)
        end
      end
    }
  end
end
