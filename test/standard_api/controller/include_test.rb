require 'standard_api/test_helper'

class ControllerIncludesTest < ActionDispatch::IntegrationTest

  # = Including an invalid include

  # = Including an invalid nested include

  test "Controller#create with a invalid nested include" do
    property_attributes = attributes_for(:property, non_include_photo: attributes_for(:photo))

    assert_difference 'Photo.count', 1 do
      post '/properties', params: { property: property_attributes }, as: :json
    end
    json = JSON.parse(response.body)
    assert_nil json['non_include_photo']
  end

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
