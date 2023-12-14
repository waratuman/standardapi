require 'standard_api/test_app'
require 'standard_api/test_helper'

module NestedAttributes
  class HasOneTest < ActionDispatch::IntegrationTest
    # include StandardAPI::TestCase
    include StandardAPI::Helpers


    # = Create Test

    test 'create record and create nested record' do
      @controller = PhotosController.new

      post photos_path, params: { photo: { camera: {make: 'Sony'}} }, as: :json

      photo = Photo.last
      assert_equal photo.id, photo.camera.photo_id
      assert_equal 'Sony', photo.camera.make
    end

    test 'create record and update nested record' do
      camera = create(:camera, make: 'Sony')

      @controller = PhotosController.new
      post photos_path, params: { photo: { camera: {id: camera.id, make: 'Nokia'} } }, as: :json

      assert_response :created
      photo = Photo.last
      assert_equal photo.id, photo.camera.photo_id
      assert_equal 'Nokia', photo.camera.make
    end

    # = Update Test

    test 'update record and create nested record' do
      photo = create(:photo)

      @controller = PhotosController.new
      put photo_path(photo), params: { photo: { camera: {make: 'Canon'}} }, as: :json

      assert_response :ok
      photo.reload
      assert_equal 'Canon', photo.camera.make
    end

    test 'update record and update nested record' do
      camera = create(:camera, make: 'Leica')
      photo = create(:photo, camera: camera)

      @controller = PhotosController.new
      put photo_path(photo), params: { photo: { camera: {make: 'Nokia'}} }, as: :json

      assert_response :ok
      photo.reload
      assert_equal 'Nokia', photo.camera.make
    end

    test 'update record and set relation to  nil' do
      camera = create(:camera, make: 'Leica')
      photo = create(:photo, camera: camera)

      @controller = PhotosController.new
      put photo_path(photo), params: { photo: { camera: nil} }, as: :json

      assert_response :ok
      photo.reload
      assert_nil photo.camera
    end

  end
end
