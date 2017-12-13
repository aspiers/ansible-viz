#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require './graphviz'
require './styler'
require 'pp'


class Legend
  def mk_legend
    styler = Styler.new
    types = [:playbook, :role, :task, :varfile, :vardefaults, :var, :template]
    nodes = Hash[*(types.flat_map {|type|
      node = styler.style(GNode[type.to_s.capitalize], type)
      [type, node]
    })]
    nodes[:varfile][:label] = "Extra vars file"
    nodes[:vardefaults][:label] = "Extra defaults file"
    nodes[:main_var] = styler.style(GNode["Var"], :var)
    nodes[:main_default] = styler.style(GNode["Default"], :var_default)
    nodes[:default_var] = styler.style(GNode["Default"], :var_default)
    nodes[:unused] = styler.style(GNode["Unused var"], :var_unused)
    nodes[:undefined] = styler.style(GNode["Undefined var"], :var_undefined)
    nodes[:fact] = styler.style(GNode["Fact / Argument"], :var_fact)
    edges = [
      GEdge[nodes[:playbook], nodes[:role], {:label => "calls"}],
      styler.style(GEdge[nodes[:playbook], nodes[:playbook], {:label => "include"}],
          :include_playbook),
      styler.style(GEdge[nodes[:playbook], nodes[:task], {:label => "calls task"}],
          :call_task),
      styler.style(GEdge[nodes[:role], nodes[:role], {:label => "includes"}], :includes_role),
      GEdge[nodes[:role], nodes[:task], {:label => "calls"}],
      GEdge[nodes[:role], nodes[:varfile], {:label => "provides"}],
      GEdge[nodes[:role], nodes[:main_var], {:label => "main vars define"}],
      GEdge[nodes[:role], nodes[:main_default], {:label => "main defaults define"}],
      GEdge[nodes[:role], nodes[:vardefaults], {:label => "provides"}],
      GEdge[nodes[:role], nodes[:template], {:label => "provides"}],
      GEdge[nodes[:vardefaults], nodes[:default_var], {:label => "define"}],
      GEdge[nodes[:varfile], nodes[:var], {:label => "defines"}],
      GEdge[nodes[:varfile], nodes[:unused], {:label => "defines"}],
      styler.style(GEdge[nodes[:task], nodes[:task], {:label => "includes"}], :includes_task),
      styler.style(GEdge[nodes[:task], nodes[:undefined], {:label => "uses"}], :use_var),
      GEdge[nodes[:task], nodes[:fact], {:label => "defines"}],
      GEdge[nodes[:task], nodes[:vardefaults], {:label => "include_vars"}],
      GEdge[nodes[:task], nodes[:default_var], {:label => "uses"}],
      GEdge[nodes[:task], nodes[:template], {:label => "applies"}],
      GEdge[nodes[:template], nodes[:var], {:label => "uses"}],
    ].flat_map {|e|
      n = GNode[e[:label]]
      n[:shape] = 'none'

      e1 = GEdge[e.snode, n]
      e2 = GEdge[n, e.dnode]
      [e1, e2].each {|ee|
        ee.attrs = e.attrs.dup
        ee[:label] = nil
      }
      e1[:arrowhead] = 'none'
      [e1, e2].each {|ee|
        ee[:weight] ||= 1
      }

      [e1, e2]
    }
    legend = Graph.new_cluster('legend')
    legend.add(*edges)
    legend[:bgcolor] = Styler.hsl(15, 3, 100)
    legend[:label] = "Legend"
    legend[:fontsize] = 36
    legend
  end
end
