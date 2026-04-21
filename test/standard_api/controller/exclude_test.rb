require 'standard_api/test_helper'

class ControllerExcludeTest < ActionDispatch::IntegrationTest

  # = ApplicationHelper backward compatibility

  test "Controller#index falls back to ApplicationHelper#excludes when no ACL excludes defined" do
    ApplicationHelper.module_eval do
      def excludes
        { account: [:email] }
      end
    end

    property = create(:property)
    account = create(:account, name: "Test User", email: "test@example.com", property: property)

    get "/accounts", params: { limit: 100 }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    account_json = json.find { |a| a['id'] == account.id }
    assert account_json.key?('name'), "Expected 'name' to be present"
    assert_not account_json.key?('email'), "Expected 'email' excluded via ApplicationHelper#excludes"
  ensure
    ApplicationHelper.module_eval { remove_method :excludes }
  end

  test "ACL excludes takes precedence over ApplicationHelper#excludes" do
    ApplicationHelper.module_eval do
      def excludes
        { property: [:name] }
      end
    end

    property = create(:property, name: "Visible Name", description: "Hidden", active: true)

    get "/properties/#{property.id}", as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json.key?('name'), "Expected ACL excludes to take precedence, 'name' should be present"
    assert_not json.key?('description'), "Expected ACL excludes to still exclude 'description' for active property"
  ensure
    ApplicationHelper.module_eval { remove_method :excludes }
  end

  # = ACL excludes

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

  # = Deep excludes applied to included associations

  test "ACL excludes with deep keys strips attributes from included associations" do
    photo = create(:photo, format: 'jpg')
    property = create(:property, name: "Active", description: "Hidden", active: true, photos: [photo])

    get "/properties/#{property.id}", params: { include: [:photos] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json.key?('description'), "Expected 'description' excluded on the property"
    assert json.key?('photos'), "Expected 'photos' to be included"
    photo_json = json['photos'].first
    assert_not photo_json.key?('format'), "Expected 'format' excluded on nested photos via deep excludes"
    assert photo_json.key?('id'), "Expected other photo attributes still present"
  end

  test "Deep excludes do not apply when parent ACL returns no nested exclude" do
    photo = create(:photo, format: 'jpg')
    property = create(:property, name: "Inactive", description: "Shown", active: false, photos: [photo])

    get "/properties/#{property.id}", params: { include: [:photos] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    photo_json = json['photos'].first
    assert photo_json.key?('format'), "Expected 'format' present when parent excludes are empty"
    assert_equal 'jpg', photo_json['format']
  end

end
