#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'test/unit'
require 'ostruct'

require './loader'
require './postprocessor'
require './varfinder'
require './scoper'


class TC_Scoper < Test::Unit::TestCase
  def setup
    @d = Loader.new.load_dir("sample")
    @role1 = @d[:role].find {|r| r[:name] == "role1" }
    @roleA = @d[:role].find {|r| r[:name] == "roleA" }
    Postprocessor.new(default_options).process(@d)
    Resolver.new.process(@d)
    VarFinder.new.process(@d)
    @s = Scoper.new
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
