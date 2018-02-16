#!/usr/bin/ruby

require 'minitest'
require 'minitest/autorun'
require 'ansible_viz/loader'

class TC_Loader < Minitest::Test
  def test_thing
    d = {}

    it = thing(d, :abc, "def", "path", {"ghi" => "jkl"})
    it2 = thing(it, :xyz, "456", "path2")

    thing1 = {:type=>:abc, :name=>"def", :fqn=>"def", "ghi"=>"jkl",
              :path=>"path", :xyz=>[it2]}
    assert_equal(thing1, it)

    thing2 = {:type=>:xyz, :name=>"456", :fqn=>"def::456",
              :path=>"path2", :parent=>it}
    assert_equal(thing2, it2)
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

    assert_has_all %w(maininc extra main), role[:varfile].smap(:name)
    role.delete(:varfile)

    assert_has_all %w(main), role[:vardefaults].smap(:name)
    role.delete(:vardefaults)

    assert_has_all %w(main task1 task2), role[:task].smap(:name)
    role.delete(:task)

    expect = thing({}, :role, "role1", "sample/roles/role1",
                   {:role_deps => ["roleA"]})
    assert_equal expect, role
  end

  def test_mk_child
    d = {}
    role = thing(d, :role, "role", "rolepath")
    varfile = Loader.new.load_thing(role, :varfile, "sample/roles/role1/vars", "main.yml")

    varfile.delete :data
    expected_role = thing({}, :role, "role", "rolepath")
    expected_varfile = thing(expected_role, :varfile, "main",
                             "sample/roles/role1/vars/main.yml",
                             {:parent => d})
    assert_equal expected_varfile, varfile
  end
end
