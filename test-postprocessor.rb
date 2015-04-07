#!/usr/bin/ruby

require 'test/unit'
require './ansible-viz'

ROLE_KEYS = :role_deps, :task, :main_task, :varfile, :vardefaults
TASK_KEYS = :data, :parent, :included_tasks, :included_varfiles, :var, :args, :included_by_tasks

class TC_PostprocessorA < Test::Unit::TestCase
  def setup
    @d = Loader.new.load_dir("sample")
    Postprocessor.new.process(@d)
    @roleA = @d[:role].find {|r| r[:name] == 'roleA' }
    @main = @roleA[:task].find {|t| t[:name] == 'main' }
    @taskA = @roleA[:task].find {|t| t[:name] == 'taskA' }
  end

  def test_role
    assert_keys @roleA, *ROLE_KEYS
    assert_has_all %w(), @roleA[:role_deps].smap(:name)
    assert_has_all %w(main taskA taskB), @roleA[:task].smap(:name)
    assert_has_all %w(main maininc extra), @roleA[:varfile].smap(:name)
    assert_has_all %w(main), @roleA[:vardefaults].smap(:name)
  end

  def test_main
    assert_keys @main, *TASK_KEYS
    assert_equal @roleA, @main[:parent]
    assert_has_all [["taskB.yml", ["meow"]]], @main[:included_tasks]
    assert_has_all %w(maininc.yml), @main[:included_varfiles]
    assert_has_all %w(factAmain), @main[:var].smap(:name)
    assert_has_all %w(), @main[:args]
    assert_has_all %w(), @main[:included_by_tasks]
  end

  def test_task
    assert_keys @taskA, *TASK_KEYS
    assert_equal @roleA, @taskA[:parent]
    assert_has_all %w(), @taskA[:included_tasks]
    assert_has_all %w(extra.yml), @taskA[:included_varfiles]
    assert_has_all %w(factAunused), @taskA[:var].smap(:name)
    assert_has_all %w(service), @taskA[:args]
    assert_has_all %w(), @taskA[:included_by_tasks]
  end

  def test_vars
    varfile = @roleA[:varfile].find {|vf| vf[:name] == 'extra' }

    assert_keys varfile, :data, :parent, :var
    assert_has_all %w(varAextra), varfile[:var].smap(:name)
    varfile[:var].each {|var|
      assert !var[:used]
      assert var[:defined]
    }
  end

  def test_playbookA
    playbookA = @d[:playbook].find {|pb| pb[:name] == 'playbookA' }

    assert_keys playbookA, :data, :include, :role, :task
    assert_has_all [], playbookA[:include]
    assert_has_all [@roleA], playbookA[:role]
    assert_has_all %w(taskA), playbookA[:task].smap(:name)
  end
end


class TC_Postprocessor1 < Test::Unit::TestCase
  def setup
    @d = Loader.new.load_dir("sample")
    Postprocessor.new.process(@d)
    @roleA = @d[:role].find {|r| r[:name] == 'roleA' }
    @role1 = @d[:role].find {|r| r[:name] == 'role1' }
    @main = @role1[:task].find {|t| t[:name] == 'main' }
    @task1 = @role1[:task].find {|t| t[:name] == 'task1' }
  end

  def test_role
    assert_keys @role1, *ROLE_KEYS
    assert_has_all %w(roleA), @role1[:role_deps]
    assert_has_all %w(main task1 task2), @role1[:task].smap(:name)
    assert_has_all %w(main maininc extra), @role1[:varfile].smap(:name)
    assert_has_all %w(main), @role1[:vardefaults].smap(:name)
  end

  def test_main
    assert_keys @main, *TASK_KEYS
    assert_equal @role1, @main[:parent]
    assert_has_all [["task2.yml", ["meow"]]], @main[:included_tasks]
    assert_has_all %w(maininc.yml), @main[:included_varfiles]
    assert_has_all %w(fact1main), @main[:var].smap(:name)
    assert_has_all %w(), @main[:args]
    assert_has_all %w(), @main[:included_by_tasks]
  end

  def test_task
    assert_keys @task1, *TASK_KEYS
    assert_equal @role1, @task1[:parent]
    assert_has_all %w(), @task1[:included_tasks]
    assert_has_all %w(fact1unused), @task1[:var].smap(:name)
    assert_has_all %w(extra.yml), @task1[:included_varfiles]
    assert_has_all %w(service), @task1[:args]
    assert_has_all %w(), @task1[:included_by_tasks]
  end

  def test_vars
    varfile = @role1[:varfile].find {|vf| vf[:name] == 'extra' }

    assert_keys varfile, :data, :parent, :var
    assert_has_all %w(var1extra), varfile[:var].smap(:name)
    varfile[:var].each {|var|
      assert !var[:used]
      assert var[:defined]
    }
  end

  def test_playbook1
    playbook1 = @d[:playbook].find {|pb| pb[:name] == 'playbook1' }

    assert_keys playbook1, :data, :include, :role, :task
    assert_has_all ["playbookA.yml"], playbook1[:include]
    assert_has_all [@role1, @roleA], playbook1[:role]
    assert_has_all %w(task1 taskA), playbook1[:task].smap(:name)
  end
end
