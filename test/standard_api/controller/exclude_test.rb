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

  test "ApplicationHelper#excludes is resolved once per request, not once per record" do
    calls = 0
    ApplicationHelper.module_eval do
      define_method(:excludes) do
        calls += 1
        { account: [:email] }
      end
    end

    property = create(:property)
    10.times { |i| create(:account, name: "A#{i}", email: "a#{i}@example.com", property: property) }

    get "/accounts", params: { limit: 100 }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json.size >= 10, "Expected the index to render every account"
    assert json.none? { |a| a.key?('email') }, "Expected 'email' excluded on every account"
    assert_equal 1, calls, "Expected ApplicationHelper#excludes to be resolved once per request"
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

  test "a zero-arity ACL excludes is still honoured, with a deprecation warning" do
    ApplicationController.class_eval do
      private def photo_excludes
        { format: true }
      end
    end

    photo = create(:photo, format: 'jpg')

    logger = ActiveSupport::LogSubscriber.logger
    warnings = []
    logger.stubs(:warn).with { |msg| warnings << msg.to_s; true }

    get "/photos/#{photo.id}", as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json.key?('format'), "Expected a zero-arity ACL excludes to still apply"
    assert warnings.any? { |w| w.include?('PhotoACL#excludes() has been deprecated') },
      "Expected a deprecation warning, got: #{warnings.inspect}"
  ensure
    ApplicationController.send(:remove_method, :photo_excludes)
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

  # = Includes that resolve to something other than a record

  test "excludes apply to an include that resolves to a plain hash" do
    camera = create(:camera, make: "Leica", hidden: true)

    get "/cameras/#{camera.id}", params: { include: [:specs] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert json.key?('specs'), "Expected 'specs' to be included"
    assert_equal 'CMOS', json['specs']['sensor'], "Expected other keys still present"
    assert_not json['specs'].key?('serial'),
      "Expected 'serial' excluded from a non-record include, got #{json['specs'].inspect}"
  end

  test "an include that resolves to a plain hash is untouched when excludes permit" do
    camera = create(:camera, make: "Leica", hidden: false)

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

  # = Custom partials
  #
  # StandardAPI only enforces excludes in application/_record. A custom model
  # partial has to resolve and apply them itself, which is what
  # `photos/_photo` demonstrates.

  test "a custom partial applies every attribute in the exclude sub-tree" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", hidden: true, photo: photo)

    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_not json['photo'].key?('format'), "Expected 'format' excluded on the nested photo"
    assert_not json['photo'].key?('created_at'), "Expected 'created_at' excluded on the nested photo"
    assert json['photo'].key?('id'), "Expected other photo attributes still present"
  end

  test "a custom partial forwards the exclude sub-tree to records it nests" do
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

  test "a custom partial renders nested records normally when excludes permit" do
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
  # requester must never be reused for a requester whose excludes differ.

  test "excluded attributes are not served from a fragment cache warmed by another requester" do
    photo = create(:photo, format: 'jpg')
    camera = create(:camera, make: "Leica", hidden: false, retired: false, photo: photo)

    # Warm the cache as a requester with no excludes on photo.
    get "/cameras/#{camera.id}", params: { include: [:photo] }, as: :json
    assert_response :ok
    assert_equal 'jpg', JSON.parse(response.body)['photo']['format']

    # Same record, a requester whose ACL hides photo.format.
    get "/cameras/#{camera.id}", params: { include: [:photo] },
      headers: { 'X-Hide-Photo-Format' => '1' }, as: :json
    assert_response :ok
    assert_not JSON.parse(response.body)['photo'].key?('format'),
      "excluded attribute leaked from a fragment cached for a different requester"
  end

  test "a requester with excludes does not poison the fragment cache for others" do
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
