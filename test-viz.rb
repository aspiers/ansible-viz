#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'

require 'simplecov'
SimpleCov.start do
  add_filter "/test"
end

require 'test/unit'
require './test-loader'
require './test-postprocessor'
require './test-grapher'
