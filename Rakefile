require 'bundler/gem_tasks'
require "rake/testtask"
require 'rspec/core/rake_task'

$LOAD_PATH.unshift File.dirname(__FILE__)

task default: :test
task test: [:minitest, :spec]

RSpec::Core::RakeTask.new(:spec)

desc "Run minitest tests"
Rake::TestTask.new do |t|
  t.name = :minitest
  t.test_files = FileList['test/**/test_*.rb']
  t.verbose = false
end
