require 'standard_api/test_helper'

module NestedAttributes
  class HasAndBelongsToManyTest < ActionDispatch::IntegrationTest
    # include StandardAPI::TestCase
    include StandardAPI::Helpers


    # = Create Test

    test 'create record and create nested record' do
      @controller = PropertiesController.new
      post properties_path, params: { property: { name: 'Beach House', photos: [{format: 'image/jpeg'}]} }, as: :json

      assert_response :created
      property = Property.last
      assert_equal 'Beach House', property.name
      assert_equal ['image/jpeg'], property.photos.map(&:format)
    end

    test 'create record and update nested record' do
      photo = create(:photo, format: 'image/png')

      @controller = PropertiesController.new
      post properties_path, params: { property: { name: 'Beach House', photos: [{id: photo.id, format: 'image/jpeg'}] } }, as: :json

      assert_response :created
      property = Property.last
      assert_equal 'Beach House', property.name
      assert_equal [photo.id], property.photos.map(&:id)
      assert_equal ['image/jpeg'], property.photos.map(&:format)
      assert_equal 'image/jpeg', photo.reload.format
    end

    # = Update Test

    test 'update record and create nested record' do
      property = create(:property)

      @controller = PropertiesController.new
      put property_path(property), params: { property: { photos: [{format: "image/tiff"}]} }, as: :json

      assert_response :ok
      assert_equal ["image/tiff"], property.reload.photos.map(&:format)
    end

    test 'update record and update nested record' do
      photo = create(:photo, format: 'image/gif')
      property = create(:property, photos: [photo])

      @controller = PropertiesController.new
      put property_path(property), params: { property: { photos: [{id: photo.id, format: "image/heic"}]} }, as: :json

      assert_response :ok
      assert_equal ['image/heic'], property.reload.photos.map(&:format)
    end

    test 'update record and set relation to an empty array' do
      photo = create(:photo, format: 'image/gif')
      property = create(:property, photos: [photo])

      @controller = PropertiesController.new
      put property_path(property), params: { property: { photos: [] } }, as: :json

      assert_response :ok
      assert_equal [], property.reload.photos
    end
    
    # = Errors Test
    
    test 'create record and create invalid nested record' do
      @controller = PhotosController.new
      post photos_path, params: { photo: { format: 'image/jpeg', properties: [{size: 1000}] } }, as: :json

      assert_response :bad_request
      assert_equal JSON.parse(response.body)["errors"], {
        "properties.name": ["can't be blank"]
      }
    end
    
    test 'update record and create invalid nested record' do
      photo = create(:photo)
      @controller = PhotosController.new
      put photo_path(photo), params: { photo: { format: 'image/jpeg', properties: [{size: 1000}] } }, as: :json

      assert_response :bad_request
      assert_equal JSON.parse(response.body)["errors"], {
        "properties.name": ["can't be blank"]
      }
    end

  end
end