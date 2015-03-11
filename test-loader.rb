#!/usr/bin/ruby

require 'test/unit'
require './ansible-viz'

class TC_Loader < Test::Unit::TestCase
  def test_thing
    d = {}
    it = thing(d, :abc, "def", {"ghi" => "jkl"})
    assert_equal({:type=>:abc, :name=>"def", "ghi"=>"jkl"}, it)
    assert_equal d[:abc]["def"], it

    it2 = thing(d, :abc, "def", {"ghi" => "jkl"})
    assert_equal it, it2
  end

  def test_ls_yml
    assert_equal ["playbook.yml"], Loader.ls_yml("sample")
    begin
      Loader.ls_yml("s")
      flunk
    rescue RuntimeError
    end
    assert_equal [], Loader.ls_yml("s", [])
  end

  def test_load_dir
    d = Loader.new.load_dir("sample")
    [:playbook, :role].each {|i| assert d.keys.include?(i), "missing #{i}" }
  end

  def test_role
    d = {}
    role = Loader.new.mk_role(d, "sample/roles", "role1")

    assert_equal 2, role[:var].keys.length
    role.delete(:var)

    assert_equal 2, role[:task].keys.length
    role.delete(:task)

    expect = thing({}, :role, "role1", {:role_deps => ["roleA"]})
    assert_equal expect, role
  end

  def test_vars
    d = {:name => "roleX"}
    vars = Loader.new.mk_vars(d, "sample/roles/role1/vars", "vars.yml")

    expect = [thing({}, :var, "key1", {:role=>d}),
              thing({}, :var, "key2", {:role=>d})]
    assert_equal expect, vars
  end

  def test_task
    d = {:name => "roleX"}
    task = Loader.new.mk_task(d, "sample/roles/role1/tasks", "task1.yml")

    task.delete(:data)
    expect = thing({}, :task, "task1", {:role=>d})
    assert_equal expect, task
  end

  def test_playbook
    d = {}
    playbook = Loader.new.mk_playbook(d, "sample", "playbook.yml")

    playbook = d[:playbook].values[0]
    assert_not_nil playbook

    playbook.delete(:data)
    expect = {:type=>:playbook, :name=>"playbook"}
    assert_equal expect, playbook
  end
end
