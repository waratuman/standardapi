require 'standard_api/test_helper'

class ControllerIncludesTest < ActionDispatch::IntegrationTest

  # = Params nested in the include of a method

  test "params nested in a method include are passed to the method" do
    camera = create(:camera)

    get "/cameras/#{camera.id}", params: { include: { readings: { status: 'inactive', range: { gt: '1' } } } }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_equal({ 'status' => 'inactive', 'range' => { 'gt' => '1' } }, json['readings']['filter'])
    assert_equal 'ActionController::Parameters', json['readings']['class']
  end

  test "the include_params hook filters the params passed to the method" do
    camera = create(:camera)

    get "/cameras/#{camera.id}", params: { include: { readings: { status: 'inactive', other: 'x' } } }, as: :json

    assert_response :ok
    assert_equal({ 'status' => 'inactive' }, JSON.parse(response.body)['readings']['filter'])
  end

  test "the include_params hook can reject the params" do
    camera = create(:camera)

    get "/cameras/#{camera.id}", params: { include: { readings: { forbidden: 'x' } } }, as: :json

    assert_response :bad_request
  end

  test "a Hash returned by the include_params hook is passed with Symbol keys" do
    camera = create(:camera)

    get "/cameras/#{camera.id}", params: { include: { history: { status: 'inactive', other: 'x' } } }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_equal({ 'status' => 'inactive' }, json['history']['filter'])
    assert_equal ['Symbol'], json['history']['keys']
  end

  test "a method include without nested params is called without any" do
    camera = create(:camera)

    get "/cameras/#{camera.id}", params: { include: [:readings] }, as: :json
    assert_response :ok
    assert_equal({}, JSON.parse(response.body)['readings']['filter'])

    get "/cameras/#{camera.id}", params: { include: { readings: true } }, as: :json
    assert_response :ok
    assert_equal({}, JSON.parse(response.body)['readings']['filter'])
  end

  test "params nested in a method include are passed on index" do
    create(:camera)

    get "/cameras", params: { limit: 100, include: { readings: { status: 'inactive' } } }, as: :json
    json = JSON.parse(response.body)

    assert_response :ok
    assert_equal({ 'status' => 'inactive' }, json.first['readings']['filter'])
  end

  test "params nested in a method include are rejected unless the ACL permits them with an empty Hash" do
    camera = create(:camera)

    get "/cameras/#{camera.id}", params: { include: { specs: { status: 'inactive' } } }, as: :json
    assert_response :bad_request
  end

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
      post "/properties", params: { property: property.attributes, include: [:accounts] }, as: :json
    end

    assert_response :bad_request
  end

  test "Controller#update with an invalid include" do
    property = create(:property, {name: "A"})
    patch "/properties/#{property.id}", params: { property: {name: "B"}, include: [:accounts] }, as: :json

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

end
