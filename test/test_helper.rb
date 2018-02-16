#!/usr/bin/ruby

require 'minitest/reporters'
Minitest::Reporters.use! [Minitest::Reporters::ProgressReporter.new(:color => true)]
require 'minitest/autorun'

require 'ansible_viz/utils'
$debug_level = 0

def assert_has_all(e, a, m="")
  if m != ""
    m += ": "
  end
  missing = e - a
  extra = a - e
  assert_equal [[], []], [missing, extra], "#{m}missing/extra items"
end

def assert_keys(it, *keys)
  base = [:type, :name, :fqn, :path]
  assert_has_all base + keys, it.keys
end

module Enumerable
  def smap(sym)
    map {|i| i[sym] }
  end
  def flat_smap(sym)
    flat_map {|i| i[sym] }
  end
end

require 'simplecov'
SimpleCov.start do
  add_filter "/test"
end
