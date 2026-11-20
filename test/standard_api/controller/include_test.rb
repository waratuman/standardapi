require 'standard_api/test_helper'

class ControllerIncludesTest < ActionDispatch::IntegrationTest

  # = Including an invalid include

  test "Controller#create with a valid include" do
    property = build(:property)

    json = assert_difference 'Property.count', 1 do
      post "/properties", params: { property: property.attributes, include: [:photos] }, as: :json
      JSON.parse(response.body)
    end

    assert_response :created
    assert_equal [], json['photos']
  end

  test "Controller#update with a valid include" do
    photo = create(:photo)
    property = create(:property, {name: "A", photos: [photo]})
    patch "/properties/#{property.id}", params: { property: {name: "B"}, include: [:photos] }, as: :json

    json = JSON.parse(response.body)
    assert_response :ok
    assert_equal [photo.id], json['photos'].map { |j| j['id'] }
  end

  # test "Controller#destroy with a valid include" do
  #   No body is returned on a destroy so includes are used
  # end

  test "Controller#create_resource with a valid include" do
    property = create(:property, accounts: [])
    account = build(:account)

    post "/properties/#{property.id}/accounts", params: { account: account.attributes, include: [:photos] }, as: :json

    json = JSON.parse(response.body)
    assert_response :created
    assert_equal [], json['photos']
  end

  # test "Controller#add_resource with a valid include" do
  #   No body is returned on a destroy so includes are used
  # end

  # test "Controller#remove_resource with an invalid include" do
  #   No body is returned on a destroy so includes are used
  # end

  # = Including an invalid include
  #
  # These tests verify that invalid includes are rejected *before* the action
  # persists any data. The `before_action :includes` on create, update, and
  # create_resource validates includes early so that a bad request is returned
  # without side effects.

  test "Controller#create with an invalid include" do
    property = build(:property)

    assert_no_difference 'Property.count' do
      post "/properties", params: { property: property.attributes, include: [:document_attachments] }, as: :json
    end

    assert_response :bad_request
  end

  test "Controller#update with an invalid include" do
    property = create(:property, {name: "A"})
    patch "/properties/#{property.id}", params: { property: {name: "B"}, include: [:document_attachments] }, as: :json

    assert_response :bad_request
    assert_equal 'A', property.reload.name
  end

  # test "Controller#destroy with an invalid include" do
  #   No body is returned on a destroy so includes are used
  # end

  test "Controller#create_resource with an invalid include" do
    property = create(:property, photos: [])
    photo = build(:photo)

    post "/properties/#{property.id}/photos", params: { photo: photo.attributes, include: [:camera] }, as: :json
    assert_equal 0, property.reload.photos.count
    assert_response :bad_request
  end

  # This test passes because includes are not used, response is a HEAD response
  # and no includes are used.
  test "Controller#add_resource with an invalid include" do
    property = create(:property, photos: [])
    photo = create(:photo)

    post "/properties/#{property.id}/photos/#{photo.id}", params: { include: [:camera] }, as: :json
    assert_equal 1, property.reload.photos.count
    assert_response :created
  end

  # This test passes because includes are not used, response is a HEAD response
  # and no includes are used.
  test "Controller#remove_resource with an invalid include" do
    photo = create(:photo)
    property = create(:property, photos: [photo])

    delete "/properties/#{property.id}/photos/#{photo.id}", params: { include: [:camera] }, as: :json
    assert_equal 0, property.reload.photos.count
    assert_response :no_content
  end

  # = Including a method

  # Render cameras with CamerasController::Policy and +declarations+, and
  # accounts with +account_policy+, for the length of the block
  def with_method_includes(declarations, account_policy = AccountPolicy)
    camera_policy = Class.new(CamerasController::Policy)
    camera_policy.class_exec(&declarations)
    policies = CamerasController.standard_api_policies.merge('camera' => camera_policy, 'account' => account_policy)
    CamerasController.stubs(:standard_api_policies).returns(policies)
    yield
  ensure
    CamerasController.unstub(:standard_api_policies)
  end

  def show_camera(camera, include)
    get "/cameras/#{camera.id}", params: { include: include }, as: :json
    assert_response :ok
    JSON.parse(response.body)
  end

  def camera_with_owner
    account = create(:account, email: 'owner@example.com')
    [create(:camera, photo: create(:photo, account: account)), account]
  end

  test "a method include that returns a record renders it with its model's Policy" do
    camera, account = camera_with_owner

    with_method_includes(-> { association :owner, types: ['Account'] }) do
      json = show_camera(camera, [:owner])
      assert_equal account.id, json['owner']['id']
      assert_equal 'owner@example.com', json['owner']['email']
    end

    with_method_includes(-> { association :owner, types: ['Account'] }, Class.new(AccountPolicy) { remove :email }) do
      json = show_camera(camera, [:owner])
      assert_equal account.id, json['owner']['id']
      assert_not json['owner'].key?('email'), "Expected 'email' hidden by the account's Policy"
    end

    hidden = Class.new(AccountPolicy) { attribute :email, unless: -> { record&.name == 'Hidden' } }
    account.update!(name: 'Hidden')
    with_method_includes(-> { association :owner, types: ['Account'] }, hidden) do
      assert_not show_camera(camera, [:owner])['owner'].key?('email'), "Expected 'email' hidden by its condition"
    end
  end

  test "a method include that returns a record renders it with the association's policy" do
    camera, account = camera_with_owner

    with_method_includes(-> { association :owner, policy: CamerasController::AccountWithoutEmailPolicy }) do
      json = show_camera(camera, [:owner])
      assert_equal account.id, json['owner']['id']
      assert_not json['owner'].key?('email'), "Expected 'email' hidden by the association's policy"
    end
  end

  test "a method include that returns a record renders what's included of it" do
    camera, _account = camera_with_owner

    with_method_includes(-> { association :owner, types: ['Account'] }, Class.new(AccountPolicy) { remove :email }) do
      json = show_camera(camera, { owner: { photos: true } })
      assert_equal [camera.photo_id], json['owner']['photos'].map { |photo| photo['id'] }
      assert_not json['owner'].key?('email')
    end
  end

  test "a method include that returns records renders each with its model's Policy" do
    camera, account = camera_with_owner

    [:owners, :owners_relation].each do |name|
      with_method_includes(-> { association name, types: ['Account'] }, Class.new(AccountPolicy) { remove :email }) do
        json = show_camera(camera, [name])
        assert_equal [account.id], json[name.to_s].map { |owner| owner['id'] }
        assert_not json[name.to_s].first.key?('email'), "Expected 'email' hidden by the account's Policy in #{name}"
      end

      with_method_includes(-> { association name, policy: CamerasController::AccountWithoutEmailPolicy }) do
        json = show_camera(camera, [name])
        assert_equal [account.id], json[name.to_s].map { |owner| owner['id'] }
        assert_not json[name.to_s].first.key?('email'), "Expected 'email' hidden by the association's policy in #{name}"
      end
    end
  end

  test "a method include that returns no records renders an empty array" do
    camera = create(:camera)

    with_method_includes(-> { associations :owners, :owners_relation, types: ['Account'] }) do
      json = show_camera(camera, [:owners, :owners_relation])
      assert_equal [], json['owners']
      assert_equal [], json['owners_relation']
    end
  end

  test "a method include that returns nil renders null" do
    camera = create(:camera)

    with_method_includes(-> { association :owner, types: ['Account'] }) do
      json = show_camera(camera, [:owner])
      assert json.key?('owner')
      assert_nil json['owner']
    end
  end

  def assert_method_include_raises(camera, name, message)
    error = assert_raises(ActionView::Template::Error) do
      get "/cameras/#{camera.id}", params: { include: [name] }, as: :json
    end
    assert_instance_of StandardAPI::MissingPolicy, error.cause
    assert_match message, error.cause.message
  end

  test "a method include that returns a model that isn't an ActiveRecord raises" do
    camera = create(:camera)

    with_method_includes(-> { association :lens }) do
      assert_method_include_raises(camera, :lens, /The include lens \(Camera#lens\) returned Lens, which has no Policy.*a model that isn't an ActiveRecord can't have a Policy/)
    end

    # Nor can the association's policy render one
    with_method_includes(-> { association :lens, policy: CamerasController::AccountWithoutEmailPolicy }) do
      assert_method_include_raises(camera, :lens, /returned Lens, which has no Policy/)
    end
  end

  test "a method include that returns an object that isn't plain JSON data raises" do
    camera = create(:camera)

    with_method_includes(-> { association :strap }) do
      assert_method_include_raises(camera, :strap, /The include strap \(Camera#strap\) returned Strap, which has no Policy/)
    end
  end

  test "a method include that returns plain JSON data renders it whole" do
    camera = create(:camera)

    with_method_includes(-> { associations :shutter_count, :settings, :specs }) do
      json = show_camera(camera, [:shutter_count, :settings, :specs])
      assert_equal 42, json['shutter_count']
      assert_equal({
        'mode' => 'manual',
        'iso' => [100, 200.5, nil, true, false],
        'calibrated_on' => '2020-01-02',
        'serviced_at' => Time.utc(2021, 3, 4, 5, 6, 7).as_json,
        'lenses' => [{ 'mount' => 'M' }]
      }, json['settings'])
      assert_equal({ 'sensor' => 'CMOS', 'serial' => 'SN-123' }, json['specs'])
    end
  end

  test "a method include that returns a record in a Hash, or among other values in an Array, raises" do
    camera, _account = camera_with_owner

    with_method_includes(-> { associations :owner_summary, :owner_and_count, types: ['Account'] }) do
      assert_method_include_raises(camera, :owner_summary, /returned Hash containing Account, which has no Policy to render with; a record renders with its Policy only when/)
      assert_method_include_raises(camera, :owner_and_count, /returned Array containing Account, which has no Policy/)
    end
  end

end
