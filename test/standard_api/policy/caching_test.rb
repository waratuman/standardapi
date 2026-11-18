require 'standard_api/test_helper'

class PolicyCachingTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  test 'varies_by_requester? is false only for unconditional declarations' do
    assert_not policy_class.varies_by_requester?
    assert_not policy_class { attribute :make, comment: 'Who made it'; remove :retired }.varies_by_requester?
    assert_not Class.new(policy_class { attribute :make, comment: 'Who made it' }).varies_by_requester?

    assert policy_class { attribute :make, if: -> { true } }.varies_by_requester?
    assert policy_class { attribute :make, unless: -> { true } }.varies_by_requester?
    assert policy_class { attributes_for(-> { :all }) { } }.varies_by_requester?
    assert Class.new(policy_class { attribute :make, if: -> { true } }).varies_by_requester?
  end

  test 'policy_varies? is whether the model\'s Policy could vary by requester' do
    ApplicationController.stubs(:standard_api_policies).returns('property' => policy_class(Property) { attribute :name, comment: 'Its name' })
    assert_not AccountsController.new.send(:policy_varies?, Property)

    ApplicationController.stubs(:standard_api_policies).returns('property' => policy_class(Property) { attribute :name, if: -> { true } })
    assert AccountsController.new.send(:policy_varies?, Property)
  end

  test 'policy_varies? with includes is whether any Policy they reach could vary' do
    varying = policy_class(Photo) { attribute :format, if: -> { true } }
    ApplicationController.stubs(:standard_api_policies).returns('account' => AccountPolicy, 'photo' => varying)
    controller = AccountsController.new

    assert_not controller.send(:policy_varies?, Account)
    assert controller.send(:policy_varies?, Account, { 'photos' => {} })
    assert_not controller.send(:policy_varies?, Account, { 'limit' => 1 })
    # A polymorphic association could be any model
    assert controller.send(:policy_varies?, Account, { 'subject' => {} })
    # So could what a method returns
    assert controller.send(:policy_varies?, Property, { 'english_name' => {} })
  end

  def property_hiding_name_by_header
    policy_class(Property) do
      attribute :name, unless: -> { request.headers['X-Hide-Name'] == '1' }
    end
  end

  test 'a hidden attribute is not served from a fragment cached for another requester' do
    ApplicationController.stubs(:standard_api_policies).returns('property' => property_hiding_name_by_header)
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name']

    get account_path(account, include: :property, format: :json), headers: { 'X-Hide-Name' => '1' }
    assert_not JSON(response.body)['property'].key?('name'),
      'hidden attribute leaked from a fragment cached for a different requester'
  end

  test 'a requester an attribute is hidden from does not poison the fragment cache' do
    ApplicationController.stubs(:standard_api_policies).returns('property' => property_hiding_name_by_header)
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json), headers: { 'X-Hide-Name' => '1' }
    assert_not JSON(response.body)['property'].key?('name')

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name'],
      'permitted attribute was hidden by a fragment cached for a restricted requester'
  end

  test 'unconditional declarations keep fragment caching' do
    ApplicationController.stubs(:standard_api_policies).returns('property' => policy_class(Property) { attribute :name, comment: 'Its name' })
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name']

    property.update_column(:name, 'Changed')
    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name'], 'expected a cache hit'
  end

end
