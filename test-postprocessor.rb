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

    assert_keys @roleA, :role_deps, :task, :main_task, :varset
    assert_has_all %w(), @roleA[:role_deps].smap(:name)
    assert_has_all %w(main taskA taskB), @roleA[:task].smap(:name)
    assert_has_all %w(defaults main maininc extra), @roleA[:varset].smap(:name)
  end

  def test_main
    main = @roleA[:task].find {|t| t[:name] == 'main' }
    Postprocessor.new.do_task(@d, main)

    assert_keys main, :data, :parent, :included_tasks, :included_varsets, :var
    assert_equal @roleA, main[:parent]
    assert_has_all %w(taskB), main[:included_tasks].smap(:name)
    assert_has_all %w(maininc), main[:included_varsets].smap(:name)
    assert_has_all %w(factAmain), main[:var].smap(:name)
  end

  def test_task
    taskA = @roleA[:task].find {|t| t[:name] == 'taskA' }
    Postprocessor.new.do_task(@d, taskA)

    assert_keys taskA, :data, :parent, :included_tasks, :included_varsets, :var
    assert_equal @roleA, taskA[:parent]
    assert_has_all %w(), taskA[:included_tasks].smap(:name)
    assert_has_all %w(extra), taskA[:included_varsets].smap(:name)
    assert_has_all %w(factAunused), taskA[:var].smap(:name)
  end

  def test_vars
    varset = @roleA[:varset].find {|vs| vs[:name] == 'extra' }
    Postprocessor.new.do_vars(@d, varset)

    assert_keys varset, :data, :parent, :var
    assert_has_all %w(varAextra), varset[:var].smap(:name)
    varset[:var].each {|var|
      assert !var[:used]
      assert var[:defined]
    }
  end

  def test_playbookA
    playbookA = Loader.new.mk_playbook(@d, "sample", "playbookA.yml")
    Postprocessor.new.do_playbook(@d, playbookA)

    assert_keys playbookA, :data, :role, :task
    assert_has_all [@roleA], playbookA[:role]
    assert_has_all %w(taskA), playbookA[:task].smap(:name)
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

    assert_keys @role1, :role_deps, :task, :main_task, :varset
    assert_has_all %w(roleA), @role1[:role_deps].smap(:name)
    assert_has_all %w(main task1 task2), @role1[:task].smap(:name)
    assert_has_all %w(defaults main maininc extra), @role1[:varset].smap(:name)
  end

  def test_main
    main = @role1[:task].find {|t| t[:name] == 'main' }
    Postprocessor.new.do_task(@d, main)

    assert_keys main, :data, :parent, :included_tasks, :included_varsets, :var
    assert_equal @role1, main[:parent]
    assert_has_all %w(task2), main[:included_tasks].smap(:name)
    assert_has_all %w(maininc), main[:included_varsets].smap(:name)
    assert_has_all %w(fact1main), main[:var].smap(:name)
  end

  def test_task
    task1 = @role1[:task].find {|t| t[:name] == 'task1' }
    Postprocessor.new.do_task(@d, task1)

    assert_keys task1, :data, :parent, :included_tasks, :included_varsets, :var
    assert_equal @role1, task1[:parent]
    assert_has_all %w(fact1unused), task1[:var].smap(:name)
    assert_has_all %w(extra), task1[:included_varsets].smap(:name)
    assert_has_all %w(), task1[:included_tasks].smap(:name)
  end

  def test_vars
    varset = @role1[:varset].find {|vs| vs[:name] == 'extra' }
    Postprocessor.new.do_vars(@d, varset)

    assert_keys varset, :data, :parent, :var
    assert_has_all %w(var1extra), varset[:var].smap(:name)
    varset[:var].each {|var|
      assert !var[:used]
      assert var[:defined]
    }
  end

  def test_playbook1
    playbook1 = Loader.new.mk_playbook(@d, "sample", "playbook1.yml")
    Postprocessor.new.do_playbook(@d, playbook1)

    assert_keys playbook1, :data, :role, :task
    assert_has_all [@role1, @roleA], playbook1[:role]
    assert_has_all %w(task1 taskA), playbook1[:task].smap(:name)
  end
end
