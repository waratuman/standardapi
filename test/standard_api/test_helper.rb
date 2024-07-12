require File.expand_path('../test_app', __FILE__)

require "minitest/autorun"
require 'minitest/unit'
require 'factory_bot'
require 'faker'
require 'standard_api/test_case'
require 'byebug'
require 'mocha/minitest'

# Setup the test db
ActiveSupport.test_order = :random

include ActionDispatch::TestProcess

class ActiveSupport::TestCase
  include ActiveRecord::TestFixtures
  include FactoryBot::Syntax::Methods

  def setup
    @routes ||= TestApplication.routes
    @subscribers, @layouts, @partials = [], {}, {}

    Rails.cache.clear

    @subscribers << ActiveSupport::Notifications.subscribe("!render_template.action_view") do |_name, _start, _finish, _id, payload|
      path = payload[:identifier]
      virtual_path = payload[:virtual_path]
      format, handler = *path.split("/").last.split('.').last(2)

      partial = virtual_path =~ /^.*\/_[^\/]*$/

      if partial
        if @partials[virtual_path]
          @partials[virtual_path][:count] += 1
        else
          @partials[virtual_path] = {
            count: 1,
            path: virtual_path,
            format: format,
            handler: handler
          }
        end
      else
        if @layouts[virtual_path]
          @layouts[virtual_path][:count] += 1
        else
          @layouts[virtual_path] = {
            count: 1,
            path: virtual_path,
            format: format,
            handler: handler
          }
        end
      end
    end
  end

  def teardown
    @subscribers.each do |subscriber|
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  # = Helper Methods

  def debug
    ActiveRecord::Base.logger = Logger.new(STDOUT)
    $debugging = true
    yield
  ensure
    ActiveRecord::Base.logger = nil
    $debugging = false
  end

  def controller_path
    if defined?(@controller)
      @controller.controller_path
    else
      controller_class.new.controller_path
    end
  end

  def path_with_action(action, options={})
    { :controller => controller_path, :action => action }.merge(options)
  end

  def assert_sql(*expected)
    return_value = nil

    queries_ran = if block_given?
      queries_ran = SQLLogger.log.size
      return_value = yield if block_given?
      SQLLogger.log[queries_ran...]
    else
      [expected.pop]
    end

    failed_patterns = []
    expected.each do |pattern|
      failed_patterns << pattern unless queries_ran.any?{ |sql| sql_equal(pattern, sql) }
    end

    assert failed_patterns.empty?, <<~MSG
      Query pattern(s) not found:
        - #{failed_patterns.map{|l| l.gsub(/\n\s*/, " ")}.join('\n  - ')}
      Queries Ran (queries_ran.size):
        - #{queries_ran.map{|l| l.gsub(/\n\s*/, "\n    ")}.join("\n  - ")}
    MSG

    return_value
  end

  def assert_no_sql(*not_expected)
    return_value = nil
    queries_ran = block_given? ? SQLLogger.log.size : 0
    return_value = yield if block_given?
  ensure
    failed_patterns = []
    queries_ran = SQLLogger.log[queries_ran...]
    not_expected.each do |pattern|
      failed_patterns << pattern if queries_ran.any?{ |sql| sql_equal(pattern, sql) }
    end
    assert failed_patterns.empty?, <<~MSG
      Unexpected Query pattern(s) found:
        - #{failed_patterns.map(&:inspect).join('\n  - ')}
      Queries Ran (queries_ran.size):
        - #{queries_ran.map{|l| l.gsub(/\n\s*/, "\n    ")}.join("\n  - ")}
    MSG

    return_value
  end
  def sql_equal(expected, sql)
    sql = sql.strip.gsub(/"(\w+)"/, '\1').gsub(/\(\s+/, '(').gsub(/\s+\)/, ')').gsub(/\s+/, ' ')
    if expected.is_a?(String)
      expected = Regexp.new(Regexp.escape(expected.strip.gsub(/"(\w+)"/, '\1').gsub(/\(\s+/, '(').gsub(/\s+\)/, ')').gsub(/\s+/, ' ')), Regexp::IGNORECASE)
    end

    expected.match(sql)
  end

  def assert_rendered(options = {}, message = nil)
    options = case options
    when NilClass, Regexp, String, Symbol
      { layout: options }
    when Hash
      options
    else
      raise ArgumentError, "assert_template only accepts a String, Symbol, Hash, Regexp, or nil"
    end

    options.assert_valid_keys(:layout, :partial, :count, :format, :handler)

    if expected_layout = options[:layout]
      case expected_layout
      when String, Symbol
        msg = message || sprintf("expecting layout <%s> but action rendered <%s>",
          expected_layout, @layouts.keys)
        assert_includes @layouts.keys, expected_layout.to_s, msg

        key = expected_layout.to_s
        value = @layouts[key]

        if expected_count = options[:count]
          actual_count = value[:count]
          msg = message || sprintf("expecting %s to be rendered %s time(s) but rendered %s time(s)",
                 expected_partial, expected_count, actual_count)
          assert_equal expected_count, actual_count, msg
        end

        if expected_format = options[:format]
          actual_format = value[:format]
          msg = message || sprintf("expecting %s to be rendered as %s but rendered as %s",
                 expected_partial, expected_format, actual_format)
          assert_equal expected_format, actual_format, msg
        end

        if expected_handler = options[:handler]
          actual_handler = value[:handler]
          msg = message || sprintf("expecting %s to be rendered as %s but rendered as %s",
                 expected_partial, expected_handler, actual_handler)
          assert_equal expected_handler, actual_handler, msg
        end
      when Regexp
        msg = message || sprintf("expecting layout <%s> but action rendered <%s>",
          expected_layout, @layouts.keys)
        assert(@layouts.keys.any? {|l| l =~ expected_layout }, msg)

        key = @layouts.keys.find {|l| l =~ expected_layout }
        value = @layouts[key]

        if expected_count = options[:count]
          actual_count = value[:count]
          msg = message || sprintf("expecting %s to be rendered %s time(s) but rendered %s time(s)",
                 expected_partial, expected_count, actual_count)
          assert_equal expected_count, actual_count, msg
        end

        if expected_format = options[:format]
          actual_format = value[:format]
          msg = message || sprintf("expecting %s to be rendered as %s but rendered as %s",
                 expected_partial, expected_format, actual_format)
          assert_equal expected_format, actual_format, msg
        end

        if expected_handler = options[:handler]
          actual_handler = value[:handler]
          msg = message || sprintf("expecting %s to be rendered as %s but rendered as %s",
                 expected_partial, expected_handler, actual_handler)
          assert_equal expected_handler, actual_handler, msg
        end
      when nil, false
        assert(@layouts.empty?, msg)
      end
    elsif expected_partial = options[:partial]
      case expected_partial
      when String, Symbol
        msg = message || sprintf("expecting partial <%s> but action rendered <%s>",
          expected_partial, @partials.keys)
        assert_includes @partials.keys, expected_partial.to_s, msg

        key = expected_partial.to_s
        value = @partials[key]

        if expected_count = options[:count]
          actual_count = value[:count]
          msg = message || sprintf("expecting %s to be rendered %s time(s) but rendered %s time(s)",
                 expected_partial, expected_count, actual_count)
          assert_equal expected_count, actual_count, msg
        end

        if expected_format = options[:format]
          actual_format = value[:format]
          msg = message || sprintf("expecting %s to be rendered as %s but rendered as %s",
                 expected_partial, expected_format, actual_format)
          assert_equal expected_format, actual_format, msg
        end

        if expected_handler = options[:handler]
          actual_handler = value[:handler]
          msg = message || sprintf("expecting %s to be rendered as %s but rendered as %s",
                 expected_partial, expected_handler, actual_handler)
          assert_equal expected_handler, actual_handler, msg
        end
      when Regexp
        msg = message || sprintf("expecting partial <%s> but action rendered <%s>",
          expected_partial, @partials.keys)
        assert(@partials.keys.any? {|l| l =~ expected_partial }, msg)

        key = @partials.keys.find {|l| l =~ expected_partial }
        value = @partials[key]

        if expected_count = options[:count]
          actual_count = value[:count]
          msg = message || sprintf("expecting %s to be rendered %s time(s) but rendered %s time(s)",
                 expected_partial, expected_count, actual_count)
          assert_equal expected_count, actual_count, msg
        end

        if expected_format = options[:format]
          actual_format = value[:format]
          msg = message || sprintf("expecting %s to be rendered as %s but rendered as %s",
                 expected_partial, expected_format, actual_format)
          assert_equal expected_format, actual_format, msg
        end

        if expected_handler = options[:handler]
          actual_handler = value[:handler]
          msg = message || sprintf("expecting %s to be rendered as %s but rendered as %s",
                 expected_partial, expected_handler, actual_handler)
          assert_equal expected_handler, actual_handler, msg
        end
      when nil, false
        assert(@partials.empty?, msg)
      end
    end
  end

  class SQLLogger
    class << self
      attr_accessor :ignored_sql, :log, :log_all
      def clear_log; self.log = []; self.log_all = []; end
    end

    self.clear_log

    self.ignored_sql = [/^PRAGMA/i, /^SELECT currval/i, /^SELECT CAST/i, /^SELECT @@IDENTITY/i, /^SELECT @@ROWCOUNT/i, /^SAVEPOINT/i, /^ROLLBACK TO SAVEPOINT/i, /^RELEASE SAVEPOINT/i, /^SHOW max_identifier_length/i, /^BEGIN/i, /^COMMIT/i]

    # FIXME: this needs to be refactored so specific database can add their own
    # ignored SQL, or better yet, use a different notification for the queries
    # instead examining the SQL content.
    oracle_ignored     = [/^select .*nextval/i, /^SAVEPOINT/, /^ROLLBACK TO/, /^\s*select .* from all_triggers/im, /^\s*select .* from all_constraints/im, /^\s*select .* from all_tab_cols/im]
    mysql_ignored      = [/^SHOW FULL TABLES/i, /^SHOW FULL FIELDS/, /^SHOW CREATE TABLE /i, /^SHOW VARIABLES /, /^\s*SELECT (?:column_name|table_name)\b.*\bFROM information_schema\.(?:key_column_usage|tables)\b/im]
    postgresql_ignored = [/^\s*select\b.*\bfrom\b.*pg_namespace\b/im, /^\s*select tablename\b.*from pg_tables\b/im, /^\s*select\b.*\battname\b.*\bfrom\b.*\bpg_attribute\b/im, /^SHOW search_path/i]
    sqlite3_ignored =    [/^\s*SELECT name\b.*\bFROM sqlite_master/im, /^\s*SELECT sql\b.*\bFROM sqlite_master/im]

    [oracle_ignored, mysql_ignored, postgresql_ignored, sqlite3_ignored].each do |db_ignored_sql|
      ignored_sql.concat db_ignored_sql
    end

    attr_reader :ignore

    def initialize(ignore = Regexp.union(self.class.ignored_sql))
      @ignore = ignore
    end

    def call(name, start, finish, message_id, values)
      sql = values[:sql]

      # FIXME: this seems bad. we should probably have a better way to indicate
      # the query was cached
      return if 'CACHE' == values[:name]

      self.class.log_all << sql
      # puts sql
      self.class.log << sql unless ignore =~ sql
    end
  end
  ActiveSupport::Notifications.subscribe('sql.active_record', SQLLogger.new)

end

class ActionController::TestCase

  def assigns(key = nil)
    assigns = {}.with_indifferent_access
    @controller.view_assigns.each { |k, v| assigns.regular_writer(k, v) }
    key.nil? ? assigns : assigns[key]
  end

end
