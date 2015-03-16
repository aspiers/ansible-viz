#!/usr/bin/ruby

require 'test/unit'
require 'ostruct'

require './ansible-viz'

class TC_Grapher < Test::Unit::TestCase
  def test_full
    g = render(Loader.new.load_dir("sample"), OpenStruct.new)
    assert_not_nil g
  end
end
