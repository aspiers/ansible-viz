#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'

def assert_has_all(e, a, m="")
  if m != ""
    m += ": "
  end
  missing = a - e
  extra = e - a
  assert_equal [[], []], [missing, extra], "#{m}missing/extra items"
end

require 'simplecov'
SimpleCov.start do
  add_filter "/test"
end

require 'test/unit'
require './test-loader'
require './test-postprocessor'
require './test-scoper'
require './test-grapher'
