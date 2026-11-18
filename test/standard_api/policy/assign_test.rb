require 'standard_api/test_helper'

class PolicyAssignTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  def policy_for(policy)
    policy.new(PropertiesController.new, Property)
  end

  test 'assigned attributes are what assign declares, each with: run for the record' do
    policy = empty_policy_class do
      assign :build_type, with: -> { record ? 'brick' : 'metal' }
      assign :name, :description, with: :default_name

      private

      def default_name = 'Hancock'
    end

    assert_equal({ 'build_type' => 'metal', 'name' => 'Hancock', 'description' => 'Hancock' }, policy_for(policy).assigned_attributes(nil))
    assert_equal 'brick', policy_for(policy).assigned_attributes(Property.new)['build_type']
    # They aren't made writable
    assert_equal [], policy_for(policy).permitted_attributes(nil)
  end

  test 'an assign on: :create or :update is assigned only on one, a model or new record being a create' do
    policy = empty_policy_class do
      assign :build_type, on: :create, with: -> { 'brick' }
      assign :description, on: :update, with: -> { 'Changed' }
    end

    assert_equal({ 'build_type' => 'brick' }, policy_for(policy).assigned_attributes(nil))
    assert_equal({ 'build_type' => 'brick' }, policy_for(policy).assigned_attributes(Property.new))
    assert_equal({ 'description' => 'Changed' }, policy_for(policy).assigned_attributes(create(:property)))
    assert_equal %w[description], policy_for(policy).assigned_attribute_names(create(:property))
  end

  test 'remove takes back an inherited assign, which an attributes_for block can declare' do
    parent = empty_policy_class { assign :build_type, :description, with: -> { 'brick' } }

    assert_equal %w[description], policy_for(Class.new(parent) { remove :build_type }).assigned_attribute_names(nil)

    keyed = empty_policy_class do
      attributes_for(-> { record&.name }) { |name| assign :description, with: -> { "About #{name}" } if name }
    end
    assert_equal({}, policy_for(keyed).assigned_attributes(nil))
    assert_equal({ 'description' => 'About Hancock' }, policy_for(keyed).assigned_attributes(Property.new(name: 'Hancock')))
  end

  test 'assign needs with:, a Symbol or a Proc, and only takes on: :create or :update' do
    assert_raises(ArgumentError) { empty_policy_class { assign :name } }
    assert_raises(ArgumentError) { empty_policy_class { assign :name, with: 'Hancock' } }
    assert_raises(ArgumentError) { empty_policy_class { assign :name, with: :name, on: :destroy } }
    error = assert_raises(ArgumentError) { empty_policy_class { assign :name, with: :name, if: :admin? } }
    assert_match(/unknown assign options for name: if/, error.message)

    # In an attributes_for block they're checked when it runs
    policy = empty_policy_class { attributes_for(-> { 1 }) { assign :name, value: 'Hancock' } }
    assert_raises(ArgumentError) { policy_for(policy).assigned_attributes(nil) }
  end

  test 'Policy::Record#assigned_attributes is empty without a Policy' do
    record_policy = StandardAPI::Policy::Record.new(ApplicationController.new, Property, nil, nil)
    assert_equal({}, record_policy.assigned_attributes)
    assert_equal [], record_policy.assigned_attribute_names
  end

  test 'POST create sets what the Policy assigns over what the client sends, writable or not' do
    policy = Class.new(PropertyPolicy) do
      assign :build_type, on: :create, with: -> { record.new_record? ? 'brick' : 'metal' }
      assign :description, with: -> { "Named #{params.dig(:property, :name)}" }
    end

    with_model_policy(Property, policy) do
      post properties_path, params: { property: { name: 'Hancock', description: 'Sent', build_type: 'concrete' } }, as: :json
    end

    assert_response :created
    property = Property.last
    assert_equal 'Hancock', property.name
    assert_equal 'Named Hancock', property.description
    assert_equal 'brick', property.build_type
  end

  test 'POST create sets what the Policy assigns without any params' do
    with_model_policy(Property, Class.new(PropertyPolicy) { assign :name, with: -> { 'Hancock' } }) do
      post properties_path, params: {}, as: :json
    end

    assert_response :created
    assert_equal 'Hancock', Property.last.name
  end

  test 'PATCH update sets only what the Policy assigns on update' do
    property = create(:property, name: 'Hancock', build_type: 'metal')
    policy = Class.new(PropertyPolicy) do
      assign :build_type, on: :create, with: -> { 'brick' }
      assign :description, on: :update, with: -> { "Was #{record.name_was}" }
    end

    with_model_policy(Property, policy) do
      patch property_path(property), params: { property: { name: 'Sears' } }, as: :json
    end

    assert_response :ok
    property.reload
    assert_equal 'Sears', property.name
    assert_equal 'Was Hancock', property.description
    assert_equal 'metal', property.build_type
  end

  test 'nested records get what their Policy assigns' do
    account = create(:account, name: 'A Co.', email: 'a@example.com')
    property = create(:property, accounts: [account])
    account_policy = Class.new(AccountPolicy) do
      assign :email, on: :create, with: -> { 'new@example.com' }
      assign :name, on: :update, with: -> { "#{record.name} (updated)" }
    end
    policy = Class.new(PropertyPolicy) { association :accounts, writable: { policy: account_policy } }

    with_model_policy(Property, policy) do
      patch property_path(property), params: { property: { accounts: [
        { id: account.id, name: 'B Co.' },
        { name: 'C Co.', email: 'c@example.com' }
      ] } }, as: :json
    end

    assert_response :ok
    assert_equal 'A Co. (updated)', account.reload.name
    assert_equal 'a@example.com', account.email
    created = property.accounts.reload.find { |a| a.id != account.id }
    assert_equal 'C Co.', created.name
    assert_equal 'new@example.com', created.email
  end

  test "write_schema.json doesn't describe what the Policy assigns as writable" do
    policy = Class.new(PropertyPolicy) do
      assign :description, with: -> { 'Set' }
      assign :name, on: :update, with: -> { 'Set' }
    end

    properties = with_model_policy(Property, policy) do
      get write_schema_properties_path(format: 'json')
      JSON(response.body).dig('properties', 'property', 'properties')
    end

    assert_not properties.key?('description')
    assert properties.key?('name')
  end

end
