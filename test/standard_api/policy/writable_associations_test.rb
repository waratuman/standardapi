require 'standard_api/test_helper'

class PolicyWritableAssociationsTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  def policy_for(policy)
    policy.new(PropertiesController.new, Property)
  end

  test 'writable associations are what association and writable declare writable' do
    policy = empty_policy_class do
      association :photos, writable: true
      association :landlord
      writable :accounts
      attribute :name, writable: true
    end

    assert_equal %w[photos accounts], policy_for(policy).permitted_associations(nil)
    # Strong parameters doesn't permit them; they're written as nested records
    assert_equal %w[name], policy_for(policy).writable_attributes(nil).keys
  end

  test 'a writable association on: :create or :update is written only on one, a model being a create' do
    policy = empty_policy_class do
      association :photos, writable: { on: :create }
      association :accounts, writable: { on: :update }
    end

    assert_equal %w[photos], policy_for(policy).permitted_associations(nil)
    assert_equal %w[photos], policy_for(policy).permitted_associations(Property.new)
    assert_equal %w[accounts], policy_for(policy).permitted_associations(create(:property))
    assert_equal %w[accounts], policy_for(policy).permitted_associations(nil, on: :update)
  end

  test 'writable: false takes back an inherited writable association, as does remove' do
    parent = empty_policy_class { associations :photos, :accounts, writable: true }

    assert_equal %w[accounts], policy_for(Class.new(parent) { association :photos, writable: false }).permitted_associations(nil)
    assert_equal %w[photos], policy_for(Class.new(parent) { remove :accounts }).permitted_associations(nil)
  end

  test "a writable association isn't changed by a condition, which decides what renders" do
    policy = empty_policy_class { association :photos, writable: true, if: -> { false } }

    assert_equal %w[photos], policy_for(policy).permitted_associations(create(:property))
  end

  test 'an association can only be writable: true, false or { on: }' do
    assert_raises(ArgumentError) { empty_policy_class { association :photos, writable: [:id] } }
    assert_raises(ArgumentError) { empty_policy_class { association :photos, writable: { permit: [:id] } } }
    assert_raises(ArgumentError) { empty_policy_class { association :photos, writable: { on: :destroy } } }

    # A standalone writable can't tell it's an association until it's asked
    policy = empty_policy_class { writable :photos, permit: [:id] }
    error = assert_raises(ArgumentError) { policy_for(policy).permitted_associations(nil) }
    assert_match(/association photos of Property can't be writable with permit:/, error.message)
  end

  test 'Policy::Record#writable_associations is empty without a Policy' do
    record_policy = StandardAPI::Policy::Record.new(ApplicationController.new, Property, nil, nil)
    assert_equal [], record_policy.writable_associations
  end

  test 'PATCH update writes only the associations the Policy makes writable on update' do
    account = create(:account, name: 'A Co.')
    property = create(:property, accounts: [account])
    policy = Class.new(PropertyPolicy) { association :accounts, writable: { on: :create } }

    with_model_policy(Property, policy) do
      patch property_path(property), params: { property: { name: 'Hancock', accounts: [{ id: account.id, name: 'B Co.' }] } }, as: :json
    end

    assert_response :ok
    assert_equal 'Hancock', property.reload.name
    assert_equal 'A Co.', account.reload.name
    # It isn't rendered as written either
    assert_not JSON.parse(response.body).key?('accounts')
  end

end
