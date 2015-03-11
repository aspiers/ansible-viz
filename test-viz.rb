#!/usr/bin/ruby

require 'test/unit'
#require 'coverage.so'
#Coverage.start

require './test-loader'
require './test-postprocessor'
require './test-grapher'
#Coverage.result.each_pair {|file, a|
#  if file !~ /ansible-viz/ or file =~ /\/test/
#    next
#  end
#  a = a.compact
#  puts "#{file}: "+ (100 * a.inject(0.0) {|acc, i| acc + i} / a.length).to_i.to_s
#}
