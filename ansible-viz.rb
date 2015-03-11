#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require 'mustache'
require 'yaml'
require 'fileutils'
require 'optparse'
require 'ostruct'
require 'pp'

require './graphviz'
require './loader'
require './postprocessor'
require './grapher'


########## RENDER #############

def write(graph, filename)
  Mustache.template_file = 'diagram.mustache'
  view = Mustache.new
  view[:now] = Time.now.strftime("%Y.%m.%d %H:%M:%S")

  view[:title] = "Ansible dependencies"
  view[:dotdata] = g2dot(graph)

  path = filename
  File.open(path, 'w') do |f|
    f.puts view.render
  end
end


########## OPTIONS #############

if __FILE__ == $0
  options = OpenStruct.new
  options.format = :hot
  options.output_filename = "viz.html"
  options.show_vars = false
  OptionParser.new do |o|
    o.banner = "Usage: ansible-viz.rb [options] <path-to-playbooks>"
    o.on("-o", "--output [FILE]", "Where to write output") do |fname|
      options.output_filename = fname
    end
    o.on("--vars",
         "Include vars. WARNING: unused/undefined support is EXPERIMENTAL.") do |val|
      options.show_vars = true
    end
    o.on_tail("-h", "--help", "Show this message") do
      puts o
      exit
    end
  end.parse!
  if ARGV.length != 1
    abort("Must provide the path to your playbooks")
  end
  options.playbook_dir = ARGV.shift

  data = Loader.new.load_dir(options.playbook_dir)
  Postprocessor.new.postprocess(data)
  graph = Grapher.new.graph(data, options)
  write(graph, options.output_filename)
end
