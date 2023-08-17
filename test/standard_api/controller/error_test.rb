require 'standard_api/test_helper'

class ControllerErrorTest < ActionDispatch::IntegrationTest

  # = Including an invalid include

  test "Controller#create with a invalid value" do
    property = build(:property, name: nil)

    post "/properties", params: { property: property.attributes }, as: :json
    
    assert_response :bad_request
    assert_equal JSON.parse(response.body)["errors"], {
      "name" => ["can't be blank"]
    }
  end

end
