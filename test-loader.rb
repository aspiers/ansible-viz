#!/usr/bin/ruby

require 'test/unit'
require './ansible-viz'

class TC_Loader < Test::Unit::TestCase
  def test_thing
    d = {}
    it = thing(d, :abc, "def", {"ghi" => "jkl"})
    it2 = thing(it, :xyz, "456")
    assert_equal({:type=>:abc, :name=>"def", :fqn=>"def", "ghi"=>"jkl", :xyz=>[it2]}, it)
    assert_equal({:type=>:xyz, :name=>"456", :fqn=>"def::456", :parent=>it}, it2)
    assert_has_all d[:abc], [it]
  end

  def test_ls_yml
    assert_has_all %w(playbook1.yml playbookA.yml), Loader.ls_yml("sample")
    begin
      Loader.ls_yml("none")
      flunk
    rescue RuntimeError
    end
    assert_equal [], Loader.ls_yml("none", [])
  end

  def test_load_dir
    d = Loader.new.load_dir("sample")
    [:playbook, :role].each {|i| assert d.keys.include?(i), "missing #{i}" }
  end

  def test_role
    d = {}
    role = Loader.new.mk_role(d, "sample/roles", "role1")

    assert_has_all %w(maininc extra main), role[:varset].smap(:name)
    role.delete(:varset)

    assert_has_all %w(main), role[:vardefaults].smap(:name)
    role.delete(:vardefaults)

    assert_has_all %w(main task1 task2), role[:task].smap(:name)
    role.delete(:task)

    expect = thing({}, :role, "role1", {:role_deps => ["roleA"]})
    assert_equal expect, role
  end

  def test_varset
    d = {}
    role = thing(d, :role, "role")
    varset = Loader.new.mk_varset(role, "sample/roles/role1/vars", "main.yml")

    varset.delete :data
    expect = thing(thing({}, :role, "role"), :varset, "main", {:parent => d})
    assert_equal expect, varset
  end

  def test_vardefaults
    role = thing({}, :role, "role")
    vardefaults = Loader.new.mk_vardefaults(role, "sample/roles/role1/defaults", "main.yml")

    vardefaults.delete :data
    expect = thing(thing({}, :role, "role"), :vardefaults, "main")
    assert_equal expect, vardefaults
  end

  def test_task
    role = thing({}, :role, "role")
    task = Loader.new.mk_task(role, "sample/roles/role1/tasks", "task1.yml")

    task.delete(:data)
    expect = thing(thing({}, :role, "role"), :task, "task1")
    assert_equal expect, task
  end

  def test_playbook
    d = {}
    playbook = Loader.new.mk_playbook(d, "sample", "playbook1.yml")

    playbook = d[:playbook][0]
    assert_not_nil playbook

    playbook.delete(:data)
    expect = thing({}, :playbook, "playbook1")
    assert_equal expect, playbook
  end
end
