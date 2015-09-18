$LOAD_PATH << File.expand_path('../lib', __FILE__)

require "minitest/autorun"
require 'minitest/unit'
require 'minitest/reporters'
require 'factory_girl'
require 'active_record'
require 'faker'
require 'standard_api'
require 'standard_api/test_case'
require 'byebug'

FactoryGirl.find_definitions

# Setup the test db
ActiveSupport.test_order = :random
require File.expand_path('../app', __FILE__)

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

class ActiveSupport::TestCase
  include ActiveRecord::TestFixtures
  include FactoryGirl::Syntax::Methods

  def setup
    @routes ||= TestApplication.routes
  end

  # = Helper Methods

  def controller_path
    @controller.controller_path
  end

  def path_with_action(action, options={})
    { :controller => controller_path, :action => action }.merge(options)
  end

end

