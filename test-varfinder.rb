#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'test/unit'
require 'ostruct'

require './loader'
require './postprocessor'
require './scoper'


class TC_FindVars < Test::Unit::TestCase
  def try(expect, input)
    role = thing({}, :role, "role", "rolepath")
    task = thing(role, :task, "task1", "taskpath")
    assert_equal expect, VarFinder.new.find_vars_in_task(task, input)
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


class TC_VarFinder < Test::Unit::TestCase
  def setup
    @d = Loader.new.load_dir("sample")
    @role1 = @d[:role].find {|r| r[:name] == "role1" }
    @roleA = @d[:role].find {|r| r[:name] == "roleA" }
    Postprocessor.new.process(@d)
    Resolver.new.process(@d)
    VarFinder.new.process(@d)
  end
end
