require File.expand_path('../app', __FILE__)

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
    Rails.cache.clear
  end

  # = Helper Methods

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

end

class ActionController::TestCase

  def assigns(key = nil)
    assigns = {}.with_indifferent_access
    @controller.view_assigns.each { |k, v| assigns.regular_writer(k, v) }
    key.nil? ? assigns : assigns[key]
  end

end
