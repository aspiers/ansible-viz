#!/usr/bin/ruby

require 'test/unit'
require 'ostruct'

require './ansible-viz'

class TC_Grapher < Test::Unit::TestCase
  def setup
    @g = Graph.new
  end

  def w
    write(@g, "test.html")
  end

  def test_full
    options = OpenStruct.new
    options.show_vars = true
    @g = render(Loader.new.load_dir("sample"), options)
    assert_not_nil @g
    w
  end

  def test_dist
    # Experiment with hidden node to assist with ranking
    skip
    n1 = GNode["1"]
    n1.data = {:type => :playbook}
    n2 = GNode["2"]
    n2.data = {:type => :none}
    n3 = GNode["3"]
    n3.data = {:type => :var}
    @g.add n1, n2, n3

    e1 = GEdge[n1, n2]
    e2 = GEdge[n2, n3]
    @g.add e1, e2

    n2[:shape] = 'none'
    n2[:width] = 0
    n2[:height] = 0
    n2[:margin] = 0
    n2[:label] = ''
    e1[:arrowhead] = 'none'

    w
  end

  def test_add_node
    var = thing({}, :var, "vvv")
    Grapher.new.add_node(@g, var)
    assert_equal 1, @g.nodes.length
    @g.nodes.each {|n| assert_equal "vvv", n[:label] }
  end

  def test_add_nodes
    d = {}
    role = thing(d, :role, "1rr")
    task = thing(role, :task, "ttt")
    thing(task, :var, "fff")  # fact
    varset = thing(role, :varset, "sss")
    var = thing(varset, :var, "vvv")
    playbook = thing(d, :playbook, "ppp", {:role => [role], :task => [task]})

    Grapher.new.add_nodes(@g, d)

    assert_equal 6, @g.nodes.length
  end
end
