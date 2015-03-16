#!/usr/bin/ruby

require 'test/unit'
require './ansible-viz'


class TC_PostprocessorA < Test::Unit::TestCase
  def setup
    @d = {}
    @roleA = Loader.new.mk_role(@d, "sample/roles", "roleA")
  end

  def test_role
    Postprocessor.new.do_role(@d, @roleA)

    assert_has_all %w(), @roleA[:role_deps].map {|d| d[:name] }
  end

  def test_task
    taskA = @roleA[:task].each_value.find {|t| t[:name] == 'taskA' }
    Postprocessor.new.do_task(@d, taskA)

    assert_has_all %w(taskB), taskA[:included_tasks].map {|v| v[:name] }
    assert_has_all %w(extra), taskA[:included_varsets].map {|v| v[:name] }
    assert_has_all %w(defA varAmain varAextra), taskA[:used_vars]
    assert_has_all %w(factAunused), taskA[:var].values.map {|v| v[:name] }
  end

  def test_vars
    varset = @roleA[:varset].each_value.find {|vs| vs[:name] == 'extra' }
    Postprocessor.new.do_vars(@d, varset)
    assert_has_all %w(varAextra), varset[:var].values.map {|v| v[:name] }
    varset[:var].each_value {|var|
      assert !var[:used]
      assert var[:defined]
    }
  end

  def test_playbookA
    playbook = Loader.new.mk_playbook(@d, "sample", "playbookA.yml")
    Postprocessor.new.do_playbook(@d, playbook)

    assert_has_all [@roleA], playbook[:role]
    assert_has_all [@roleA[:task]["taskA"]], playbook[:task]
  end
end


class TC_Postprocessor1 < Test::Unit::TestCase
  def setup
    @d = {}
    @roleA = Loader.new.mk_role(@d, "sample/roles", "roleA")
    @role1 = Loader.new.mk_role(@d, "sample/roles", "role1")
  end

  def test_role
    Postprocessor.new.do_role(@d, @role1)

    assert_has_all %w(roleA), @role1[:role_deps].map {|d| d[:name] }
  end

  def test_task
    task1 = @role1[:task].each_value.find {|t| t[:name] == 'task1' }
    Postprocessor.new.do_task(@d, task1)

    assert_has_all %w(fact1unused), task1[:var].values.map {|v| v[:name] }
    assert_has_all %w(def1 var1main var1extra
                      defA varAmain varAextra), task1[:used_vars]
    assert_has_all %w(extra), task1[:included_varsets].map {|v| v[:name] }
    assert_has_all %w(task2), task1[:included_tasks].map {|v| v[:name] }
  end

  def test_vars
    varset = @role1[:varset].each_value.find {|vs| vs[:name] == 'extra' }
    Postprocessor.new.do_vars(@d, varset)
    assert_has_all %w(var1extra), varset[:var].values.map {|v| v[:name] }
    varset[:var].each_value {|var|
      assert !var[:used]
      assert var[:defined]
    }
  end

  def test_playbook1
    playbook = Loader.new.mk_playbook(@d, "sample", "playbook1.yml")
    Postprocessor.new.do_playbook(@d, playbook)

    assert_has_all [@role1, @roleA], playbook[:role]
    assert_has_all [@role1[:task]["task1"],
                    @roleA[:task]["taskA"]],
                   playbook[:task]
  end
end


class TC_Scope < Test::Unit::TestCase
  def setup
    skip
    @d = Loader.new.load_dir("sample")
    @role1 = @d[:role]["role1"]
    @roleA = @d[:role]["roleA"]
    Postprocessor.new.postprocess(@d)
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
