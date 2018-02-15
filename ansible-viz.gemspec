# -*- encoding: utf-8 -*-
#require File.expand_path("../lib/guard/sclang/version", __FILE__)

Gem::Specification.new do |s|
  s.name         = "ansible-viz"
  s.author       = "Alexis Lee, Adam Spiers"
  s.email        = "ansible@adamspiers.org"
  s.summary      = "Guard gem for visualising Ansible playbooks"
  s.homepage     = "http://github.com/aspiers/ansible-viz"
  s.license      = "Apache 2.0"
  s.version      = "0.1.0"  # FIXME: Ansible::Viz::VERSION

  s.description  = <<-DESC
    ansible-viz generates web-based visualisations of the relationships between
    components within Ansible playbooks, using Graphviz.
  DESC

  s.add_dependency 'rake'
  s.add_dependency 'mustache', '~> 0.99.4'
  s.add_dependency 'word_wrap'
  s.add_development_dependency 'pry'
  s.add_development_dependency 'rspec', '~> 3.7'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'test-unit-minitest'
  s.add_development_dependency 'simplecov'

  s.files        = %w(README.md LICENSE)
  s.files       += %w(diagram.mustache viz.js)
  s.files       += Dir["*.rb"]
end
