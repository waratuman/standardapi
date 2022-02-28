require 'standard_api/test_helper'

class ControllerIncludesTest < ActionDispatch::IntegrationTest

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
  # end
  
  test "Controller#create_resource with an invalid include" do
    property = create(:property, photos: [])
    photo = build(:photo)

    post "/properties/#{property.id}/photos", params: { photo: photo.attributes, include: [:camera] }, as: :json
    assert_equal 0, property.reload.photos.count
    assert_response :bad_request
  end
  
  test "Controller#add_resource with an invalid include" do
    property = create(:property, photos: [])
    photo = build(:photo)

    post "/properties/#{property.id}/photos/#{photo.id}", params: { include: [:camera] }, as: :json
    assert_equal 0, property.reload.photos.count
    assert_response :bad_request
  end
  
  test "Controller#remove_resource with an invalid include" do
    photo = create(:photo)
    property = create(:property, photos: [photo])

    delete "/properties/#{property.id}/photos/#{photo.id}", params: { include: [:camera] }, as: :json
    assert_equal 1, property.reload.photos.count
    assert_response :bad_request
  end

end
