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
    @routes ||= if defined?(TestApplication)
      TestApplication.routes
    else
      SortTestApplication.routes
    end
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

  def assert_sql(sql, &block)
    queries = []
    callback = -> (*, payload) do
      queries << payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)

    assert_not_nil queries.map { |x| x.strip.gsub(/\s+/, ' ') }.
      find { |x| x == sql.strip.gsub(/\s+/, ' ') }
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

end

class ActionController::TestCase

  def assigns(key = nil)
    assigns = {}.with_indifferent_access
    @controller.view_assigns.each { |k, v| assigns.regular_writer(k, v) }
    key.nil? ? assigns : assigns[key]
  end

end
