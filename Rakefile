require 'bundler/setup'
require "bundler/gem_tasks"

require 'fileutils'
require 'rake/testtask'

# Test Task
Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList.new('test/standard_api/**/*_test.rb') do |fl|
    fl.exclude('test/standard_api/controller/custom_order_test.rb')
  end
end

Rake::TestTask.new("test_order_param_name") do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/standard_api/controller/custom_order_test.rb']
end

Rake::TestTask.new('benchmark') do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/standard_api/performance.rb']
  # t.warning = true
  # t.verbose = true
end
