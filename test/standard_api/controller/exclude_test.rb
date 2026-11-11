require 'standard_api/test_helper'

class ControllerExcludeTest < ActionDispatch::IntegrationTest

  test "Schemas.load! raises if ApplicationHelper#excludes is defined" do
    ApplicationHelper.module_eval do
      def excludes
        { account: [:email] }
      end
    end

    error = assert_raises(StandardAPI::InvalidConfiguration) { StandardAPI::Schemas.load! }
    assert_match(/ApplicationHelper#excludes is no longer supported/, error.message)
  ensure
    ApplicationHelper.module_eval { remove_method :excludes }
  end

  # = Schema conditions
  #
  # These use the Camera resource, which isn't exercised by the generic
  # StandardAPI::TestCase suite (unlike Property/Account), so what
  # CamerasController::Schema hides per record can be demonstrated here
  # without affecting that much larger, resource-agnostic test suite.

  test "Controller#show leaves out an attribute the Schema hides for the record" do
    camera = create(:camera, make: "Leica", hidden: true)

    get "/cameras/#{camera.id}", as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_nil json['make'], "Expected 'make' to be excluded for a hidden camera"
    assert_not json.key?('make'), "Expected 'make' key to not be present for a hidden camera"
  end

  test "Controller#show renders an attribute the Schema shows for the record" do
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

  # = Includes that resolve to something other than a record

  test "an include that resolves to a plain hash is rendered whole" do
    camera = create(:camera, make: "Leica", hidden: true)

    get "/cameras/#{camera.id}", params: { include: [:specs] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_equal 'SN-123', json['specs']['serial']
  end

  # = Validation errors

  test "validation errors for an excluded attribute are withheld" do
    post "/cameras", params: { camera: { make: nil, hidden: true } }, as: :json
    json = JSON.parse(response.body)

    assert_response :bad_request
    assert_not json.key?('make'), "Expected 'make' excluded for a hidden camera"
    assert_not json['errors'].key?('make'),
      "Expected the error for the excluded 'make' to be withheld, got #{json['errors'].inspect}"
  end

  test "validation errors are reported when the attribute is not excluded" do
    post "/cameras", params: { camera: { make: nil, hidden: false } }, as: :json
    json = JSON.parse(response.body)

    assert_response :bad_request
    assert json['errors'].key?('make'), "Expected the 'make' error reported for a visible camera"
  end

  # = Narrowing included associations

  test "an association's schema strips attributes from the included record" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", hidden: true, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json.key?('make'), "Expected 'make' excluded on the camera"
    assert json.key?('photo'), "Expected 'photo' to be included"
    assert_not json['photo'].key?('format'), "Expected 'format' excluded on the nested photo by its schema"
    assert json['photo'].key?('id'), "Expected other photo attributes still present"
  end

  test "an included record isn't narrowed when the association's schema gives none" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", hidden: false, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json['photo'].key?('format'), "Expected 'format' present when the photo isn't narrowed"
    assert_equal 'jpg', json['photo']['format']
  end

  test "an association's schema narrows every record in a has_many association" do
    schema = Class.new(AccountSchema) { association :photos, schema: CamerasController::PhotoWithoutFormatSchema }
    schemas = ApplicationController.standard_api_schemas.merge('account' => schema)
    ApplicationController.stubs(:standard_api_schemas).returns(schemas)

    account = create(:account, name: "Ansel", email: "ansel@example.com")
    photos = [
      create(:photo, account: account, format: 'jpg'),
      create(:photo, account: account, format: 'png')
    ]

    get "/accounts", params: { include: [:photos], limit: 100 }, as: :json
    json = JSON.parse(response.body).find { |item| item['id'] == account.id }

    assert_response :ok
    assert_equal photos.map(&:id).sort, json['photos'].map { |photo| photo['id'] }.sort
    assert json['photos'].none? { |photo| photo.key?('format') },
      "Expected every has_many record narrowed"
  ensure
    ApplicationController.unstub(:standard_api_schemas)
  end

  test "an association the Schema hides for the record isn't rendered at all" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", retired: true, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json.key?("photo"), "Expected the photo of a retired camera left out"
  end

  # = Custom partials
  #
  # StandardAPI only applies Schemas in application/_record. A custom model
  # partial has to resolve and apply what they hide itself, which is what
  # `photos/_photo` demonstrates.

  test "a custom partial applies what narrows its record" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", hidden: true, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json['photo'].key?('format'), "Expected 'format' excluded on the nested photo"
    assert_not json['photo'].key?('created_at'), "Expected 'created_at' excluded on the nested photo"
    assert json['photo'].key?('id'), "Expected other photo attributes still present"
  end

  test "a custom partial forwards what narrows the records it nests" do
    account = create(:account, name: "Ansel", email: "ansel@example.com")
    photo = create(:photo, format: 'jpg', account: account)
    camera = create(:camera, make: "Leica", hidden: true, photo: photo)

    get "/cameras/#{camera.id}", params: { include: { photo: [:account] } }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json['photo'].key?('account'), "Expected the nested account to be included"
    assert json['photo']['account'].key?('name'), "Expected other account attributes present"
    assert_not json['photo']['account'].key?('email'),
      "Expected 'email' excluded two levels down, via the custom partial"
  end

  test "a custom partial renders nested records normally when nothing narrows them" do
    account = create(:account, name: "Ansel", email: "ansel@example.com")
    photo = create(:photo, format: 'jpg', account: account)
    camera = create(:camera, make: "Leica", hidden: false, photo: photo)

    get "/cameras/#{camera.id}", params: { include: { photo: [:account] } }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_equal "ansel@example.com", json['photo']['account']['email']
    assert_equal 'jpg', json['photo']['format']
  end

  # = Fragment caching
  #
  # Cache keys are built from record timestamps only (see
  # StandardAPI::Helpers#association_cache_key), so a fragment rendered for one
  # requester must never be reused for one whose Schema hides more.

  test "hidden attributes are not served from a fragment cache warmed by another requester" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", hidden: false, retired: false, photo: photo)

    # Warm the cache as a requester whose photo is not narrowed.
    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    assert_response :ok
    assert_equal 'jpg', JSON.parse(response.body)['photo']['format']

    # Same record, a requester whose Schema hides photo.format.
    get "/cameras/#{camera.id}", params: { include: [:photo] },
      headers: { 'X-Hide-Photo-Format' => '1' }, as: :json
    assert_response :ok
    assert_not JSON.parse(response.body)['photo'].key?('format'),
      "excluded attribute leaked from a fragment cached for a different requester"
  end

  test "a restricted requester does not poison the fragment cache for others" do
    photo = create(:photo, format: 'png')
    camera = create(:camera, make: "Nikon", hidden: false, retired: false, photo: photo)

    # Render first as the restricted requester.
    get "/cameras/#{camera.id}", params: { include: [:photo] },
      headers: { 'X-Hide-Photo-Format' => '1' }, as: :json
    assert_response :ok
    assert_not JSON.parse(response.body)['photo'].key?('format')

    # An unrestricted requester must still see the attribute.
    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    assert_response :ok
    assert_equal 'png', JSON.parse(response.body)['photo']['format'],
      "permitted attribute was hidden by a fragment cached for a restricted requester"
  end

  test "an association the Schema can hide still renders when it shows it" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", retired: false, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json.key?("photo"), "Expected the photo of a camera that is not retired"
    assert_equal photo.id, json['photo']['id']
  end

end
