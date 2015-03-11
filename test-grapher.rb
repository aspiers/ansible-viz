#!/usr/bin/ruby

require 'test/unit'
require './ansible-viz'

class TC_Grapher < Test::Unit::TestCase
  def test_full
    options = OpenStruct.new
    d = Loader.new.load_dir("sample")
    Postprocessor.new.postprocess(d)
    g = Grapher.new.graph(d, options)
    assert_not_nil g
  end
end
