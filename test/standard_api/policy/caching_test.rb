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

  test 'varies_by_requester? is true for conditions, values and policies given to the plural forms' do
    assert_not empty_policy_class { attributes :make, :model, orderable: true }.varies_by_requester?
    assert_not empty_policy_class { associations :photos, :account, orderable: true }.varies_by_requester?

    assert empty_policy_class { attributes :make, :model, if: -> { true } }.varies_by_requester?
    assert empty_policy_class { attributes :make, :model, unless: -> { true } }.varies_by_requester?
    assert empty_policy_class { attributes :make, :model, value: -> { 'x' } }.varies_by_requester?

    assert empty_policy_class { associations :photos, :account, if: -> { true } }.varies_by_requester?
    assert empty_policy_class { associations :photos, :account, unless: -> { true } }.varies_by_requester?
    assert empty_policy_class { associations :photos, :account, policy: -> { nil } }.varies_by_requester?
    assert empty_policy_class { associations :photos, :account, policy: :photo_policy }.varies_by_requester?

    varying = empty_policy_class { attribute :name, if: -> { true } }
    assert empty_policy_class { associations :photos, :account, policy: varying }.varies_by_requester?
    unvarying = empty_policy_class { attribute :name }
    assert_not empty_policy_class { associations :photos, :account, policy: unvarying }.varies_by_requester?
  end

  test 'varies_by_requester? of a Policy that gives itself to an association' do
    policy = empty_policy_class { attributes :id, :name }
    policy.association :children, policy: policy
    assert_not policy.varies_by_requester?
    assert_not Class.new(policy).varies_by_requester?

    policy.attribute :email, if: -> { true }
    assert policy.varies_by_requester?
    assert Class.new(policy).varies_by_requester?
  end

  test 'varies_by_requester? of Policies that give each other to an association' do
    a = empty_policy_class { attributes :id, :name }
    b = empty_policy_class { attributes :id, :name }
    c = empty_policy_class { attributes :id, :name }
    a.association :b, policy: b
    b.association :c, policy: c
    c.association :a, policy: a
    c.association :b, policy: b
    # Asked twice, as the first answer mustn't be left behind for the second
    2.times { [a, b, c].each { |policy| assert_not policy.varies_by_requester? } }

    c.attribute :email, if: -> { true }
    2.times { [a, b, c].each { |policy| assert policy.varies_by_requester? } }
  end

  test 'varies_by_requester? that raises does not leave the Policy looking unvarying' do
    policy = empty_policy_class { attribute :name, if: -> { true } }
    policy.policy_steps = [{ varies: -> { raise 'failed' } }.freeze] + policy.policy_steps

    assert_raises(RuntimeError) { policy.varies_by_requester? }
    assert_raises(RuntimeError) { policy.varies_by_requester? }
  end

  test 'the plural forms check their options when declared, like the singular ones' do
    other = empty_policy_class
    assert_raises(ArgumentError) { empty_policy_class { attributes :make, :model, value: 'x' } }
    assert_raises(ArgumentError) { empty_policy_class { attributes :make, :model, writable: { policy: other } } }
    assert_raises(ArgumentError) { empty_policy_class { associations :photos, :account, policy: Object } }
    assert_raises(ArgumentError) { empty_policy_class { associations :photos, :account, types: [1] } }
    assert_raises(ArgumentError) { empty_policy_class { associations :photos, :account, filterable: [:eq] } }
    assert_raises(ArgumentError) { empty_policy_class { associations :photos, :account, writable: [:id] } }
    assert_raises(ArgumentError) { empty_policy_class { associations :photos, :account, policy: other, writable: true } }
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

  test 'attributes hidden with the plural form are not served from a fragment cached for another requester' do
    policy = empty_policy_class do
      attributes :id
      attributes :name, :description, unless: -> { request.headers['X-Hide-Name'] == '1' }
    end
    ApplicationController.stubs(:standard_api_policies).returns('property' => policy)
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name']

    get account_path(account, include: :property, format: :json), headers: { 'X-Hide-Name' => '1' }
    assert_not JSON(response.body)['property'].key?('name'),
      'hidden attribute leaked from a fragment cached for a different requester'
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
