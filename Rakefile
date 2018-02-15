$LOAD_PATH.unshift File.dirname(__FILE__)

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)
task default: :test

task test: [:minitest, :spec]

task :minitest do
  require 'test-viz'
end
