require 'test_helper'

class PropertiesController < ActionController::StandardAPI

  private

  def property_params
    [:name, :aliases, :description, :constructed, :size, :active]
  end

  def property_orders
    [:id, :updated_at, :created_at, :name]
  end

  def property_includes
    [:photos]
  end

end

class PropertiesControllerTest < ActionController::TestCase
  include ActionController::StandardAPI::TestCase

end
