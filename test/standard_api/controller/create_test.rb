require 'standard_api/test_helper'

class PropertiesControllerTest < ActionDispatch::IntegrationTest

  # = Include Test
  
  class Property < ActiveRecord::Base
    has_many :accounts
  end
  
  test "Controller#create with an invalid include" do
    property = build(:property)
    
    assert_no_difference 'Property.count' do
      post "/properties", params: { property: property.attributes, include: [:accounts] }, as: :json
    end

    assert_response :bad_request
  end

  test "Controller#update with an invalid include"
  test "Controller#destroy with an invalid include"
  test "Controller#create_resource with an invalid include"
  test "Controller#add_resource with an invalid include"
  test "Controller#remove_resource with an invalid include"

end
