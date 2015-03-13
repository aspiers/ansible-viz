#!/usr/bin/ruby

require 'test/unit'
require './ansible-viz'


class TC_Postprocessor < Test::Unit::TestCase
  def setup
    @d = {}
    @role1 = Loader.new.mk_role(@d, "sample/roles", "role1")
    @roleA = Loader.new.mk_role(@d, "sample/roles", "roleA")
    @pp = Postprocessor.new
  end

  def test_task
    task = @role1[:task].each_value.find {|t| t[:name] == 'task1' }
    @pp.do_task(@d, task)

    assert_equal %w(fact1 fact2), task[:fact]
    assert_equal %w(var1 var2 factA), task[:used_vars]
  end

  def test_var
    var = @role1[:var].each_value.find {|v| v[:name] == 'var1' }
    @pp.do_var(@d, var)
    assert_equal false, var[:used]
    assert_equal true, var[:defined]
  end

  def test_playbook
    playbook = Loader.new.mk_playbook(@d, "sample", "playbook.yml")
    @pp.do_playbook(@d, playbook)

    assert_equal [@role1], playbook[:role]
    assert_equal [@role1[:task]["task1"], @roleA[:task]["taskA"]], playbook[:task]
  end

  def test_role
    @pp.do_role(@d, @role1)

    assert_equal [@roleA], @role1[:role_deps]
    # Check that the tasks + vars have been postprocessed
    task = @role1[:task]["task1"]
    assert_equal %w(fact1 fact2), task[:fact]
    assert_equal %w(var1 var2 factA), task[:used_vars]
  end

  def test_var_definition
    @pp.do_role(@d, @roleA)
    @pp.do_role(@d, @role1)
    @pp.calc_defined_vars(@d, @roleA)
    @pp.calc_defined_vars(@d, @role1)

    assert_equal %w(varA varB), @roleA[:defined_vars].map {|v| v[:name] }
    @roleA[:defined_vars].each {|v|
      assert_equal true, v[:defined]
      assert_equal false, v[:used]
    }
    assert_equal %w(varA varB), @roleA[:used_vars]
    assert_equal %w(factA factB), @roleA[:fact]
    assert_equal %w(factA factB), @roleA[:all_facts]

    assert_equal %w(var1 var2 varA varB), @role1[:defined_vars].map {|v| v[:name] }
    @role1[:defined_vars].each {|v|
      assert_equal true, v[:defined]
      assert_equal false, v[:used]
    }
    assert_equal %w(var1 var1_up var2 factA varA varB), @role1[:used_vars]
    assert_equal %w(fact3 fact1 fact2), @role1[:fact]
    assert_equal %w(fact3 fact1 fact2 factA factB), @role1[:all_facts]
  end

  def test_var_usage
    up = [@roleA, @role1]
    up.each {|role| @pp.do_role(@d, role) }
    up.each {|role| @pp.calc_defined_vars(@d, role) }
    up.reverse.each {|role| @pp.check_used_vars(@d, role) }

    assert_equal %w(var1 var1_up var2 factA varA varB), @role1[:used_vars].map {|v| v[:name] }
    @role1[:used_vars].each {|v| assert_equal true, v[:used] }
    @role1[:used_vars].each {|v| assert_equal v[:name] != 'var1_up', v[:defined], "checking #{v[:name]}" }
    assert_equal %w(varA varB), @roleA[:used_vars].map {|v| v[:name] }
    @roleA[:used_vars].each {|v| assert_equal true, v[:used] }
    @roleA[:used_vars].each {|v| assert_equal true, v[:defined] }
  end
end

class TC_FindVars < Test::Unit::TestCase
  def try(expect, input)
    assert_equal expect, Postprocessor.new.find_vars(input)
  end

  def test_str
    try %w(def), "abc {{def}} ghi"
  end

  def test_list
    try %w(1 2), ["{{1}}", "{{2}}"]
  end

  def test_hash
    try %w(1 2), {:a => "{{1}}", :b => "{{2}}"}
  end

  def test_nesting
    try %w(1 2 3), {:a => ["{{1}}", "{{2}}"], :b => "{{3}}"}
  end

  def test_bar
    try %w(1 2), "{{1|up(2)}}"
  end

  def test_stdout
    try [], "{{1.stdout}}"
  end

  def test_complex
    try %w(1 2), "{{1 | up(2 | default({}))}}"
  end
end
