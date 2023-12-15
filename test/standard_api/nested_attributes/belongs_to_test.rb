require 'standard_api/test_app'
require 'standard_api/test_helper'

module NestedAttributes
  class BelongsToTest < ActionDispatch::IntegrationTest
    # include StandardAPI::TestCase
    include StandardAPI::Helpers


    # = Create Test

    test 'create record and create nested record' do
      @controller = PhotosController.new
      post photos_path, params: { photo: { account: {name: 'Big Ben'}} }, as: :json

      assert_response :created
      photo = Photo.last
      assert_equal 'Big Ben', photo.account.name
    end
  
    test 'create record and update nested record' do
      account = create(:account, name: 'Big Ben')
    
      @controller = PhotosController.new
      post photos_path, params: { photo: { account: {id: account.id, name: 'Little Jimmie'}} }, as: :json


      assert_response :created
      photo = Photo.last
      assert_equal account.id, photo.account_id
      assert_equal 'Little Jimmie', photo.account.name
    end

    # = Update Test
  
    test 'update record and create nested record' do
      photo = create(:photo)

      @controller = PhotosController.new
      put photo_path(photo), params: { photo: { account: {name: 'Big Ben'}} }, as: :json
    
      assert_response :ok
      photo.reload
      assert_equal 'Big Ben', photo.account.name
    end

    test 'update record and update nested record' do
      account = create(:account, name: 'Big Ben')
      photo = create(:photo, account: account)

      @controller = PhotosController.new
      put photo_path(photo), params: { photo: { account: {name: 'Little Jimmie'}} }, as: :json
    
      assert_response :ok
      photo.reload
      assert_equal 'Little Jimmie', photo.account.name
    end

    test 'update record and set relation to  nil' do
      account = create(:account, name: 'Big Ben')
      photo = create(:photo, account: account)

      @controller = PhotosController.new
      put photo_path(photo), params: { photo: { account: nil} }, as: :json
    
      assert_response :ok
      photo.reload
      assert_nil photo.account
    end

  end
end
