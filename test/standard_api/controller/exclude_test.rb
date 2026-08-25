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
        { camera: [:retired] }
      end
    end

    camera = create(:camera, make: "Leica", hidden: true)

    get "/cameras/#{camera.id}", as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json.key?('retired'), "Expected ACL excludes to take precedence, 'retired' should be present"
    assert_not json.key?('make'), "Expected ACL excludes to still exclude 'make' for a hidden camera"
  ensure
    ApplicationHelper.module_eval { remove_method :excludes }
  end

  # = ACL excludes
  #
  # These use the Camera resource, which isn't exercised by the generic
  # StandardAPI::TestCase suite (unlike Property/Account), so per-record ACL
  # excludes can be demonstrated here without affecting that much larger,
  # resource-agnostic test suite.

  test "Controller#show excludes attributes returned by ACL excludes" do
    camera = create(:camera, make: "Leica", hidden: true)

    get "/cameras/#{camera.id}", as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_nil json['make'], "Expected 'make' to be excluded for a hidden camera"
    assert_not json.key?('make'), "Expected 'make' key to not be present for a hidden camera"
  end

  test "Controller#show includes attributes when ACL excludes returns empty" do
    camera = create(:camera, make: "Leica", hidden: false)

    get "/cameras/#{camera.id}", as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json.key?('make'), "Expected 'make' key to be present for a visible camera"
    assert_equal "Leica", json['make']
  end

  test "Controller#index excludes attributes per-record" do
    hidden_camera = create(:camera, make: "Hidden Make", hidden: true)
    visible_camera = create(:camera, make: "Visible Make", hidden: false)

    get "/cameras", params: { limit: 100 }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok

    hidden_json = json.find { |c| c['id'] == hidden_camera.id }
    visible_json = json.find { |c| c['id'] == visible_camera.id }

    assert_not hidden_json.key?('make'), "Expected 'make' excluded for hidden camera"
    assert visible_json.key?('make'), "Expected 'make' present for visible camera"
    assert_equal "Visible Make", visible_json['make']
  end

  test "Controller#create excludes attributes in response" do
    post "/cameras", params: {
      camera: { make: "New Camera", hidden: true }
    }, as: :json
    json = JSON.parse(response.body)

    assert_response :created
    assert_not json.key?('make'), "Expected 'make' excluded in create response for a hidden camera"
  end

  test "Controller#update excludes attributes in response" do
    camera = create(:camera, make: "Old Camera", hidden: false)

    patch "/cameras/#{camera.id}", params: {
      camera: { hidden: true }
    }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json.key?('make'), "Expected 'make' excluded after updating to hidden"
  end

  # = Deep excludes applied to included associations

  test "ACL excludes with deep keys strips attributes from included associations" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", hidden: true, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json.key?('make'), "Expected 'make' excluded on the camera"
    assert json.key?('photo'), "Expected 'photo' to be included"
    assert_not json['photo'].key?('format'), "Expected 'format' excluded on the nested photo via deep excludes"
    assert json['photo'].key?('id'), "Expected other photo attributes still present"
  end

  test "Deep excludes do not apply when parent ACL returns no nested exclude" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", hidden: false, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json['photo'].key?('format'), "Expected 'format' present when parent excludes are empty"
    assert_equal 'jpg', json['photo']['format']
  end

  test "ACL excludes with a terminal true on an association key drops the whole relationship" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", retired: true, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json.key?('photo'), "Expected 'photo' association dropped entirely by excludes"
  end

  test "Association dropped via excludes still renders when parent excludes permit it" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", retired: false, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json.key?('photo'), "Expected 'photo' included when excludes empty"
    assert_equal photo.id, json['photo']['id']
  end

end
