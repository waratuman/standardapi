require 'standard_api/test_helper'

module NestedAttributes
  class HasManyTest < ActionDispatch::IntegrationTest
    # include StandardAPI::TestCase
    include StandardAPI::Helpers


    # = Create Test

    test 'create record and create nested record' do
      @controller = PropertiesController.new
      post properties_path, params: { property: { name: 'Beach House', accounts: [{name: 'Billabong'}]} }, as: :json

      assert_response :created
      property = Property.last
      assert_equal 'Beach House', property.name
      assert_equal ['Billabong'], property.accounts.map(&:name)
    end
  
    test 'create record and update nested record' do
      account = create(:account, name: 'Coco Chanel')

      @controller = PropertiesController.new
      post properties_path, params: { property: { name: 'Beach House', accounts: [{id: account.id, name: 'Crazy Chanel'}]} }, as: :json

      assert_response :created
      property = Property.last
      assert_equal [account.id], property.accounts.map(&:id)
      assert_equal ['Crazy Chanel'], property.accounts.map(&:name)
      assert_equal 'Crazy Chanel', account.reload.name
    end

    # = Update Test

    test 'update record and create nested record' do
      property = create(:property)

      @controller = PropertiesController.new
      put property_path(property), params: { property: { accounts: [{name: "Hersey's"}]} }, as: :json

      assert_response :ok
      assert_equal ["Hersey's"], property.accounts.map(&:name)
    end

    test 'update record and update nested record' do
      account = create(:account, name: 'A Co.')
      property = create(:property, name: 'Empire State Building', accounts: [account])

      @controller = PropertiesController.new
      put property_path(property), params: { property: { name: 'John Hancock Center', accounts: [{id: account.id, name: "B Co."}]} }, as: :json

      assert_response :ok
      property.reload
      assert_equal 'John Hancock Center', property.name
      assert_equal ['B Co.'], property.accounts.map(&:name)
    end

    test 'update record and set relation to an empty array' do
      account = create(:account, name: 'A Co.')
      property = create(:property, name: 'Empire State Building', accounts: [account])

      @controller = PropertiesController.new
      put property_path(property), params: { property: { accounts: [] } }, as: :json

      assert_response :ok
      property.reload
      assert_equal [], property.accounts
    end
    
    test 'update record and include nested record in response' do
      account = create(:account, name: 'A Co.')
      property = create(:property, name: 'Empire State Building', accounts: [account])

      @controller = PropertiesController.new
      put property_path(property), params: { property: { name: 'John Hancock Center', accounts: [{id: account.id, name: "B Co."}]} }, as: :json

      attributes = JSON.parse(response.body)
      assert_response :ok
      assert_equal account.id, attributes["accounts"][0]["id"]
      assert_equal "B Co.", attributes["accounts"][0]["name"]
    end

  end
end