#!/usr/bin/ruby

require 'test/unit'
require './ansible-viz'

class TC_Loader < Test::Unit::TestCase
end

class TC_FindVars < Test::Unit::TestCase
  def setup
    @l = Loader.new
  end

  def try(expect, input)
    assert_equal expect, @l.find_vars(input)
  end

  def test_str
    try ["def"], "abc {{def}} ghi"
  end

  def test_list
    try ["1", "2"], ["{{1}}", "{{2}}"]
  end

  def test_hash
    try ["1", "2"], {:a => "{{1}}", :b => "{{2}}"}
  end

  def test_nesting
    try ["1", "2", "3"], {:a => ["{{1}}", "{{2}}"], :b => "{{3}}"}
  end

  def test_bar
    try ["1", "2"], "{{1|up(2)}}"
  end

  def test_stdout
    try [], "{{1.stdout}}"
  end

  def test_complex
    try ["1", "2"], "{{1 | up(2 | default({}))}}"
  end
end
