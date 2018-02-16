#!/usr/bin/ruby

require 'minitest/autorun'
require 'ostruct'

require_relative 'test_helper'
require 'ansible_viz/grapher'
require 'ansible_viz/cli'

class TC_Grapher < Minitest::Test
  def setup
    @g = Graph.new
  end

  def w
#    write(@g, "test.html")
  end

  def test_full
    options = default_options
    options.playbook_dir = "/path/to/playbook"
    @g = graph_from_data(Loader.new.load_dir("sample"), options)
    assert ! @g.nil?
    w
  end

  def test_add_node
    d = {}
    role = thing(d, :role, "role", "rolepath")
    var = thing(role, :var, "var", "varpath")
    Grapher.new.add_node(@g, var)
    assert_equal 1, @g.nodes.length
    @g.nodes.each {|n| assert_equal "role::var", n[:label] }
  end

  def test_add_nodes
    d = {}
    role = thing(d, :role, "rrr", "rolepath")
    task = thing(role, :task, "ttt", "taskpath")
    thing(task, :var, "fff", "fff/varpath")  # fact
    varfile = thing(role, :varfile, "sss", "sss/varpath")
    thing(varfile, :var, "vvv", "vvv/varpath")
    role[:vardefaults] = []
    role[:template] = []
    thing(d, :playbook, "ppp", "playbookpath",
          {:role => [role], :task => [task]})

    styler = Styler.new
    Grapher.new.add_nodes(@g, d, styler, true)

    assert_equal 6, @g.nodes.length
  end
end
