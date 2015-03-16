#!/usr/bin/ruby

require 'test/unit'
require 'ostruct'

require './loader'
require './postprocessor'
require './scoper'


class TC_Scoper < Test::Unit::TestCase
  def setup
    skip
    @d = Loader.new.load_dir("sample")
    @role1 = @d[:role].find {|r| r[:name] == "role1" }
    @roleA = @d[:role].find {|r| r[:name] == "roleA" }
    Postprocessor.new.process(@d)
    Scoper.new.process(@d)
  end

  def test_scope
    scopes = [[@roleA, "main", %w(fAmain vAmain vAmaininclude)],
              [@roleA, "taskA", %w(fAtask1 fAtask2 vAmain vAvars)],
              [@role1, "_ptask", %w(vAmain f1ptask)],
              [@role1, "task2", %w(vAmain fact3)],
              [@role1, "task1", %w(vAmain f1ptask f1task1 f1task2 var1 var2)]]
    scopes.each {|role, tn, scope|
      assert_not_nil role[:task][tn]
      assert_not_nil role[:task][tn][:scope], "#{role[:name]} #{tn}"
      assert_has_all scope, role[:task][tn][:scope].map {|v| v[:name]}, "#{role[:name]} #{tn}"
    }
  end

  def test_var_usage
    skip  # FIXME
    pp = Postprocessor.new
    up = [@roleA, @role1]
    up.each {|role| pp.do_role(@d, role) }
    up.each {|role| pp.calc_scope(@d, role) }
    up.reverse.each {|role| pp.check_used_vars(@d, role) }

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
