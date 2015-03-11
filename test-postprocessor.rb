#!/usr/bin/ruby

require 'test/unit'
require './ansible-viz'


class TC_Postprocessor < Test::Unit::TestCase
  def setup
    @d = {}
  end

  def test_task
    role = Loader.new.mk_role(@d, "sample/roles", "role1")
    task = role[:task].each_value.find {|t| t[:name] == 'task1' }
    Postprocessor.new.do_task(@d, task)

    assert_equal %w(fact1 fact2), task[:facts]
    assert_equal %w(var1 var2), task[:used_vars]
  end

  def test_playbook
    role1 = Loader.new.mk_role(@d, "sample/roles", "role1")
    roleA = Loader.new.mk_role(@d, "sample/roles", "roleA")
    playbook = Loader.new.mk_playbook(@d, "sample", "playbook.yml")
    Postprocessor.new.do_playbook(@d, playbook)

    assert_equal [role1], playbook[:roles]
    assert_equal [role1[:task]["task1"], roleA[:task]["taskA"]], playbook[:tasks]
  end

  def test_var
  end

  def test_role_1
    role1 = Loader.new.mk_role(@d, "sample/roles", "role1")
    roleA = Loader.new.mk_role(@d, "sample/roles", "roleA")
    Postprocessor.new.do_role_1(@d, role1)

    assert_equal [roleA], role1[:role_deps]
    # Check that the tasks + vars have been postprocessed
    task = role1[:task]["task1"]
    assert_equal %w(fact1 fact2), task[:facts]
    assert_equal %w(var1 var2), task[:used_vars]
  end

  def test_role_2
    role1 = Loader.new.mk_role(@d, "sample/roles", "role1")
    roleA = Loader.new.mk_role(@d, "sample/roles", "roleA")
    @d[:role].each_value {|role| Postprocessor.new.do_role_1(@d, role) }
    Postprocessor.new.do_role_2(@d, role1)

    assert_equal [roleA], role1[:role_deps]
    assert_equal %w(key1 key1_up var1 var2), role1[:used_vars]
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
