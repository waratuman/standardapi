require 'standard_api/test_helper'

class ControllerExcludeTest < ActionDispatch::IntegrationTest

  test "Controller#show excludes attributes returned by ACL excludes" do
    property = create(:property, name: "Active Place", description: "Secret details", active: true)

    get "/properties/#{property.id}", as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_equal "Active Place", json['name']
    assert_nil json['description'], "Expected 'description' to be excluded for active properties"
    assert_not json.key?('description'), "Expected 'description' key to not be present for active properties"
  end

  test "Controller#show includes attributes when ACL excludes returns empty" do
    property = create(:property, name: "Inactive Place", description: "Visible details", active: false)

    get "/properties/#{property.id}", as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_equal "Inactive Place", json['name']
    assert json.key?('description'), "Expected 'description' key to be present for inactive properties"
    assert_equal "Visible details", json['description']
  end

  test "Controller#index excludes attributes per-record" do
    active_property = create(:property, name: "Active", description: "Hidden", active: true)
    inactive_property = create(:property, name: "Inactive", description: "Shown", active: false)

    get "/properties", params: { limit: 100, order: :id }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok

    active_json = json.find { |p| p['id'] == active_property.id }
    inactive_json = json.find { |p| p['id'] == inactive_property.id }

    assert_not active_json.key?('description'), "Expected 'description' excluded for active property"
    assert inactive_json.key?('description'), "Expected 'description' present for inactive property"
    assert_equal "Shown", inactive_json['description']
  end

  test "Controller#create excludes attributes in response" do
    post "/properties", params: {
      property: { name: "New Place", description: "Post-create", active: true }
    }, as: :json
    json = JSON.parse(response.body)

    assert_response :created
    assert_not json.key?('description'), "Expected 'description' excluded in create response for active property"
  end

  test "Controller#update excludes attributes in response" do
    property = create(:property, name: "Old Name", description: "Details", active: false)

    patch "/properties/#{property.id}", params: {
      property: { active: true }
    }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json.key?('description'), "Expected 'description' excluded after updating to active"
  end

end
