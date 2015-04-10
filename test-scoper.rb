#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'test/unit'
require 'ostruct'

require './loader'
require './postprocessor'
require './scoper'


class TC_FindVars < Test::Unit::TestCase
  def try(expect, input)
    role = thing({}, :role, "role")
    task = thing(role, :task, "task1")
    assert_equal expect, Scoper.new.find_vars_in_task(task, input)
  end

  def test_str
    try %w(def), "abc {{def}} ghi"
  end

  def test_list
    try %w(a b), ["{{a}}", "{{b}}"]
  end

  def test_hash
    try %w(a b), {:a => "{{a}}", :b => "{{b}}"}
  end

  def test_nesting
    try %w(a b c), {:a => ["{{a}}", "{{b}}"], :b => "{{c}}"}
  end

  def test_bar
    try %w(a b), "{{a|up(b)}}"
  end

  def test_stdout
    try [], "{{a.stdout}}"
  end

  def test_complex
    try %w(a b), "{{a | up(b | default({}))}}"
  end

  def test_array
    try %w(con), "{{ con['aaa-bbb']['ccc'] }}"
  end
end


class TC_Scoper < Test::Unit::TestCase
  def setup
    @d = Loader.new.load_dir("sample")
    @role1 = @d[:role].find {|r| r[:name] == "role1" }
    @roleA = @d[:role].find {|r| r[:name] == "roleA" }
    Postprocessor.new.process(@d)
    Resolver.new.process(@d)
    @s = Scoper.new
  end

  def test_find_var_uses
    taskA = @roleA[:task].find {|t| t[:name] == 'taskA' }
    task1 = @role1[:task].find {|t| t[:name] == 'task1' }
    @s.find_var_uses(@d, taskA)
    @s.find_var_uses(@d, task1)
    assert_not_nil taskA[:used_vars]
    assert_not_nil task1[:used_vars]
    assert_has_all %w(defA varAmain varAextra factB), taskA[:used_vars]
    assert_has_all %w(def1 var1main var1extra fact2
                      defA varAmain varAextra factB), task1[:used_vars]
  end

  def test_order_tasks
    expect = %w(taskB main taskA task2 main task1)
    assert_equal expect, @s.order_tasks([@role1, @roleA]).smap(:name)
    assert_equal expect, @s.order_tasks([@roleA, @role1]).smap(:name)
  end

  def test_scope
    @s.process(@d)
    mainApre = %w(defA varAmain factB meow)
    mainA = mainApre + %w(varAmaininc factAmain)
    main1pre = mainA + %w(def1 var1main fact2)
    main1 = main1pre + %w(var1maininc fact1main)
    scopes = [[@roleA, "taskB", mainApre + %w(factB)],
              [@roleA, "main", mainA],
              [@roleA, "taskA", mainA + %w(varAextra factB factAunused service)],
              [@role1, "task2", main1pre + %w(fact2)],
              [@role1, "main", main1],
              [@role1, "task1", main1 + %w(var1extra fact2 fact1unused service)]]
    scopes.each {|role, tn, scope|
      task = role[:task].find {|t| t[:name] == tn }
      assert_not_nil task
      assert_not_nil task[:scope], "#{role[:name]} #{tn}"
      assert_has_all scope, task[:scope].smap(:name), "#{role[:name]} #{tn}"
    }
  end

  def test_var_usage
    @s.process(@d)

#    task_by_name = Hash[*(task[:scope].flat_map {|v| [v[:name], v] })]
  end
end
