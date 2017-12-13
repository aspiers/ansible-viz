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

  def hsl(h, s, l)
    Styler.hsl(h, s, l)
  end

  def initialize
    @style = {
      # Node styles
      :playbook => {
        :shape => 'folder',
        :style => 'filled',
        :fillcolor => hsl(13, 40, 100)},
      :role => {
        :shape => 'house',
        :style => 'filled',
        :fillcolor => hsl(76, 45, 100)},
      :task => {
        :shape => 'octagon',
        :style => 'filled',
        :fillcolor => hsl(66, 45, 100)},
      :varfile => {
        :shape => 'box3d',
        :style => 'filled',
        :fillcolor => hsl(33, 90, 100)},
      :vardefaults => {
        :shape => 'box3d',
        :style => 'filled',
        :fillcolor => hsl(33, 60, 80)},
      :var => {
        :shape => 'oval',
        :style => 'filled',
        :fillcolor => hsl(33, 60, 95)},
      :var_default   => {
        :style => 'filled',
        :fillcolor => hsl(33, 60, 80)},
      :var_fact      => {
        :style => 'filled',
        :fillcolor => hsl(33, 80, 100)},
      :template => {
        :shape => 'note',
        :style => 'filled',
        :fillcolor => hsl(44, 65, 90)},

      # Node decorations
      :var_unused    => {:style => 'filled',
                         :fillcolor => hsl(88, 50, 100),
                         :fontcolor => hsl(0, 0, 0)},
      :var_undefined => {:style => 'filled',
                         :fillcolor => hsl(88, 100, 100)},

      # Edge styles
      :use_var => {:color => hsl(0, 0, 85),
                   :tooltip => 'uses var'},
      :applies_template => {:color => hsl(44, 65, 90)},
#                            :penwidth => 2, :style => 'dashed'},
      :call_task => {:color => 'blue', :penwidth => 2, :style => 'dashed'},
      :include => {:color => hsl(33, 100, 40), :penwidth => 2, :style => 'dashed'},
      :include_playbook => :include,
      :includes_role => :include,
      :includes_task => :include,
      :private => {:color => 'red', :penwidth => 2, :style => 'dashed'},
    }
  end

  def style(node_or_edge, style)
    while style.is_a?(Symbol)
      style = @style[style] || {}
    end
    style.each_pair {|k,v| node_or_edge[k] = v }
    node_or_edge
  end

  def decorate(g, dict, options)
    g.nodes.each {|node|
      data = node.data
      type = data[:type]
      style(node, type)
      node[:label] = data[:name]
      typename = case type
                 when :varfile then "Vars"
                 else type.to_s.capitalize
                 end
      node[:tooltip] = "#{typename} #{data[:fqn]}&#10;from #{data[:path]}"

      case type
      when :var
        if data[:used].length == 0
          style(node, :var_unused)
          node[:tooltip] += '. UNUSED.'
        elsif not data[:defined]
          style(node, :var_undefined)
          node[:tooltip] += '. UNDEFINED.'
        elsif data[:parent][:type] == :vardefaults
          style(node, :var_default)
        elsif data[:parent][:type] == :task
          style(node, :var_fact)
        end
      end
    }
  end
end
