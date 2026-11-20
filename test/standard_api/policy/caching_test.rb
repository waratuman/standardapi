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

  # The fragment cache outlives a deploy, so its keys have to tell what the
  # Policy declared when the fragment was rendered

  test 'an attribute a Policy stops declaring is not served from a fragment cached before it did' do
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    # Before the deploy: the Policy declares name
    ApplicationController.stubs(:standard_api_policies).returns('property' => policy_class(Property))
    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name']

    # After it: the same Policy, without name. Nothing about the record changed.
    ApplicationController.stubs(:standard_api_policies).returns('property' => policy_class(Property) { remove :name })
    get account_path(account, include: :property, format: :json)
    assert JSON(response.body)['property'].key?('id')
    assert_not JSON(response.body)['property'].key?('name'),
      'an attribute the Policy no longer declares was served from a fragment cached before it changed'
  end

  test 'an attribute a nested Policy stops declaring is not served from a fragment cached before it did' do
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)
    photo = create(:photo, account: account)
    columns = Photo.column_names + ['account_cached_at', 'account_property_cached_at']
    Photo.stubs(:column_names).returns(columns)
    Photo.any_instance.stubs(:account_cached_at).returns(1.day.ago)
    Photo.any_instance.stubs(:account_property_cached_at).returns(1.day.ago)
    policies = ApplicationController.standard_api_policies

    get photo_path(photo, include: { account: { property: true } }, format: :json)
    assert_equal 'The Shard', JSON(response.body)['account']['property']['name']

    # The account fragment renders the property inside it
    ApplicationController.stubs(:standard_api_policies).returns(policies.merge('property' => policy_class(Property) { remove :name }))
    get photo_path(photo, include: { account: { property: true } }, format: :json)
    assert JSON(response.body)['account']['property'].key?('id')
    assert_not JSON(response.body)['account']['property'].key?('name'),
      'an attribute a nested Policy no longer declares was served from a fragment cached before it changed'
  end

  test 'two Policies for the same model do not share a fragment' do
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)
    without_name = policy_class(Property) { remove :name }
    with_name = policy_class(Property)

    # As two base controllers, each with its own Policy for Property, would
    ApplicationController.stubs(:standard_api_policies).returns('property' => without_name)
    get account_path(account, include: :property, format: :json)
    assert_not JSON(response.body)['property'].key?('name')

    ApplicationController.stubs(:standard_api_policies).returns('property' => with_name)
    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name'],
      'a fragment cached with another Policy for the model was served'

    ApplicationController.stubs(:standard_api_policies).returns('property' => without_name)
    get account_path(account, include: :property, format: :json)
    assert_not JSON(response.body)['property'].key?('name'),
      'a fragment cached with another Policy for the model was served'
  end

  test 'policy_cache_key tells Policies for the same model apart by name' do
    declarations = proc { attributes :id, :name }
    stub_const = ->(name) { Class.new(StandardAPI::Policy, &declarations).tap { |policy| policy.stubs(:name).returns(name) } }
    keys = ['AdminPropertyPolicy', 'PublicPropertyPolicy', 'AdminPropertyPolicy'].map do |name|
      ApplicationController.stubs(:standard_api_policies).returns('property' => stub_const.(name))
      AccountsController.new.send(:policy_cache_key, Property)
    end

    assert_not_equal keys[0], keys[1]
    assert_equal keys[0], keys[2]
  end

  test 'policy_cache_key covers the Policies of what is included, and the policy an association gives' do
    registered = ApplicationController.standard_api_policies
    key = ->(policies, includes) do
      ApplicationController.stubs(:standard_api_policies).returns(registered.merge(policies))
      AccountsController.new.send(:policy_cache_key, Photo, includes)
    ensure
      ApplicationController.unstub(:standard_api_policies)
    end
    without_name = policy_class(Property) { remove :name }
    without_id = policy_class(Property) { remove :id }
    account_without_name = Class.new(AccountPolicy) { association :property, policy: without_name }
    account_without_id = Class.new(AccountPolicy) { association :property, policy: without_id }

    assert_equal key.({}, {}), key.({}, {})
    assert_not_equal key.({}, {}), key.({}, { 'account' => {} })

    # Property's Policy only counts when a property is rendered
    assert_equal key.({}, { 'account' => {} }), key.({ 'property' => without_name }, { 'account' => {} })
    assert_not_equal key.({}, { 'account' => { 'property' => {} } }),
      key.({ 'property' => without_name }, { 'account' => { 'property' => {} } })

    # So does the Policy an association gives in its place
    assert_equal key.({ 'account' => account_without_name }, { 'account' => {} }),
      key.({ 'account' => account_without_id }, { 'account' => {} })
    assert_not_equal key.({ 'account' => account_without_name }, { 'account' => { 'property' => {} } }),
      key.({ 'account' => account_without_id }, { 'account' => { 'property' => {} } })
  end

  test 'cache_digest is that of what a Policy declares, inherited or not' do
    declarations = proc do
      attributes :id, :name, orderable: true
      attribute :description, comment: 'About it'
      association :accounts
    end
    policy = empty_policy_class(&declarations)

    assert_match(/\A\h+\z/, policy.cache_digest)
    assert_equal policy.cache_digest, empty_policy_class(&declarations).cache_digest
    assert_equal policy.cache_digest, Class.new(policy).cache_digest

    assert_not_equal policy.cache_digest, Class.new(policy) { remove :name }.cache_digest
    assert_not_equal policy.cache_digest, Class.new(policy) { attribute :aliases }.cache_digest
    assert_not_equal policy.cache_digest, Class.new(policy) { attribute :description, comment: 'Changed' }.cache_digest
    assert_not_equal policy.cache_digest, Class.new(policy) { association :accounts, policy: AccountPolicy }.cache_digest
  end

  test 'cache_digest is computed once, until the Policy declares more' do
    policy = empty_policy_class { attributes :id, :name }
    digest = policy.cache_digest
    ActiveSupport::Digest.expects(:hexdigest).never
    assert_equal digest, policy.cache_digest
    ActiveSupport::Digest.unstub(:hexdigest)

    policy.remove :name
    assert_not_equal digest, policy.cache_digest
  end

  test 'cache_digest identifies a Proc by where it is defined, not by the object' do
    build = -> { empty_policy_class { attribute :name, if: -> { true }; attributes_for(:account_id) { attribute :rank, :integer } } }
    assert_equal build.().cache_digest, build.().cache_digest

    moved = empty_policy_class do
      attribute :name, if: -> { true }; attributes_for(:account_id) { attribute :rank, :integer }
    end
    assert_not_equal build.().cache_digest, moved.cache_digest
  end

end
