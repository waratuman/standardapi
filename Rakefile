require 'bundler/setup'
require "bundler/gem_tasks"

require 'fileutils'
require 'rake/testtask'

ENCODERS = %w(jbuilder turbostreamer)

namespace :test do
  ENCODERS.each do |encoder|
    Rake::TestTask.new(encoder => ["#{encoder}:env"]) do |t|
      t.libs << 'lib' << 'test'
      t.test_files = FileList[ARGV[1] ? ARGV[1] : 'test/**/*_test.rb']
      t.warning = true
      t.verbose = false
    end

    namespace encoder do
      task(:env) { ENV["TSENCODER"] = encoder }
    end
  end

  desc "Run test with all encoders"
  task all: ENCODERS.shuffle.map{ |e| "test:#{e}" }
end

task test: "test:all"

Rake::TestTask.new('benchmark') do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/standard_api/performance.rb']
  # t.warning = true
  # t.verbose = true
end
