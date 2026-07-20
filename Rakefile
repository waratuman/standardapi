require 'bundler/setup'
require "bundler/gem_tasks"

require 'fileutils'
require 'rake/testtask'

ENCODERS = %w(jbuilder turbostreamer)
ADAPTERS = %w(postgresql sqlite3)

namespace :test do
  ENCODERS.product(ADAPTERS).each do |encoder, adapter|
    task_name = "#{encoder}_#{adapter}"

    Rake::TestTask.new(task_name => ["#{task_name}:env"]) do |t|
      t.libs << 'lib' << 'test'
      t.test_files = FileList[ARGV[1] ? ARGV[1] : 'test/**/*_test.rb']
      t.warning = true
      t.verbose = false
    end

    namespace task_name do
      task(:env) { ENV["TSENCODER"] = encoder; ENV["DB_ADAPTER"] = adapter }
    end
  end

  ENCODERS.each do |encoder|
    desc "Run #{encoder} tests"
    task encoder => [encoder].product(ADAPTERS).shuffle.map { |e, a| "test:#{e}_#{a}" }
  end

  ADAPTERS.each do |adapter|
    desc "Run #{adapter} tests"
    task adapter => ENCODERS.product([adapter]).shuffle.map { |e, a| "test:#{e}_#{a}" }
  end
  
  desc "Run test with all encoders and adapters"
  task all: ENCODERS.product(ADAPTERS).shuffle.map { |e, a| "test:#{e}_#{a}" }
end

task test: "test:all"

Rake::TestTask.new('benchmark') do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/standard_api/performance.rb']
  # t.warning = true
  # t.verbose = true
end
