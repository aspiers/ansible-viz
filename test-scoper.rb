#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'test/unit'
require 'ostruct'

require './loader'
require './postprocessor'
require './scoper'


class TC_FindVars < Test::Unit::TestCase
  def try(expect, input)
    assert_equal expect, Scoper.new.find_vars(input)
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


class TC_Scoper < Test::Unit::TestCase
  def setup
    @d = Loader.new.load_dir("sample")
    @role1 = @d[:role].find {|r| r[:name] == "role1" }
    @roleA = @d[:role].find {|r| r[:name] == "roleA" }
    Postprocessor.new.process(@d)
    @s = Scoper.new
  end

  def test_find_var_usages
    @s.find_var_usages(@d)
    taskA = @roleA[:task].find {|t| t[:name] == 'taskA' }
    task1 = @role1[:task].find {|t| t[:name] == 'task1' }
    assert_not_nil taskA[:used_vars]
    assert_not_nil task1[:used_vars]
    assert_has_all %w(defA varAmain varAextra), taskA[:used_vars]
    assert_has_all %w(def1 var1main var1extra
                      defA varAmain varAextra), task1[:used_vars]
  end

  def test_dep_order
    l = [@role1, @roleA]
    assert_equal %w(roleA role1), @s.dep_order(l).smap(:name)
    assert_equal [@role1, @roleA], l
    assert_equal %w(roleA role1), @s.dep_order([@roleA, @role1]).smap(:name)
  end

  def test_scope
    @s.process(@d)
    mainA = %w(defA varAmain)
    main1 = mainA + %w(def1 var1main)
    scopes = [[@roleA, "main", mainA + %w(varAmaininc factAmain)],
              [@roleA, "taskB", mainA + %w(factB)],
              [@roleA, "taskA", mainA + %w(varAextra factB factAunused)],
              [@role1, "task2", main1 + %w(fact2)],
              [@role1, "task1", main1 + %w(var1extra fact2 fact1unused)]]
    scopes.each {|role, tn, scope|
      task = role[:task].find {|t| t[:name] == tn }
      assert_not_nil task
      assert_not_nil task[:scope], "#{role[:name]} #{tn}"
      assert_has_all scope, task[:scope].smap(:name), "#{role[:name]} #{tn}"
    }
  end

  def test_var_usage
    skip  # FIXME
    @s.process(@d)

    assert_has_all %w(var1 var1_up var2 factA varA varB), @role1[:used_vars].map {|v| v[:name] }
    @role1[:used_vars].each {|v| assert v[:used] }
    @role1[:used_vars].each {|v|
      cond = v[:name] != 'var1_up'
      assert_equal cond, v[:defined], "checking #{v[:name]}"
    }
    assert_has_all %w(varA varB), @roleA[:used_vars].map {|v| v[:name] }
    @roleA[:used_vars].each {|v| assert v[:used] }
    @roleA[:used_vars].each {|v| assert v[:defined] }
  end
end
