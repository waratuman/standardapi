require 'standard_api/test_helper'

class PolicyFilterTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  def policy_for(policy)
    policy.new(PropertiesController.new, Property)
  end

  def permitted(**params)
    ActionController::Parameters.new(params).permit!
  end

  test 'a filter, a block or a Symbol, runs on the Policy for the record and is given the params' do
    policy = empty_policy_class do
      filter { |params| params[:name] = "#{params[:name]} (#{record ? 'record' : 'model'})" }
      filter :drop_description

      private

      def drop_description(params) = params.delete(:description)
    end

    params = permitted(name: 'Hancock', description: 'Tall')
    assert_same params, policy_for(policy).filter_params(Property.new, params)
    assert_equal({ 'name' => 'Hancock (record)' }, params.to_h)
    assert_equal({ 'name' => 'Hancock (model)' }, policy_for(policy).filter_params(nil, permitted(name: 'Hancock')).to_h)
  end

  test 'a Proc filter runs like a block' do
    policy = empty_policy_class { filter ->(params) { params[:name] = name_for(record) } }
    policy.define_method(:name_for) { |record| "Built #{record.build_type}" }

    params = policy_for(policy).filter_params(Property.new(build_type: 'brick'), permitted(name: 'Sent'))
    assert_equal 'Built brick', params[:name]
  end

  test 'a filter on: :create or :update runs only on one, a model or new record being a create' do
    policy = empty_policy_class do
      filter(on: :create) { |params| params[:build_type] = 'brick' }
      filter(on: :update) { |params| params[:description] = 'Changed' }
    end

    assert_equal({ 'build_type' => 'brick' }, policy_for(policy).filter_params(nil, permitted).to_h)
    assert_equal({ 'build_type' => 'brick' }, policy_for(policy).filter_params(Property.new, permitted).to_h)
    assert_equal({ 'description' => 'Changed' }, policy_for(policy).filter_params(create(:property), permitted).to_h)
  end

  test 'filters run in the order declared, inherited ones first' do
    parent = empty_policy_class { filter { |params| params[:name] = [*params[:name], 'parent'] } }
    child = Class.new(parent) do
      filter { |params| params[:name] += ['child'] }
      filter { |params| params[:name] += ['last'] }
    end

    assert_equal %w[parent child last], policy_for(child).filter_params(nil, permitted)[:name]
    assert_equal %w[parent], policy_for(parent).filter_params(nil, permitted)[:name]
  end

  test 'an attributes_for block can declare a filter for the records of its key' do
    policy = empty_policy_class do
      attributes_for(-> { record&.name }) do |name|
        filter { |params| params[:description] = "About #{name}" } if name
      end
    end

    assert_equal({}, policy_for(policy).filter_params(nil, permitted).to_h)
    assert_equal({ 'description' => 'About Hancock' }, policy_for(policy).filter_params(Property.new(name: 'Hancock'), permitted).to_h)
  end

  test 'filter needs one Symbol, Proc or block, and only takes on: :create or :update' do
    assert_raises(ArgumentError) { empty_policy_class { filter } }
    assert_raises(ArgumentError) { empty_policy_class { filter 'name' } }
    assert_raises(ArgumentError) { empty_policy_class { filter(:name) { |params| params } } }
    assert_raises(ArgumentError) { empty_policy_class { filter :name, on: :destroy } }
    error = assert_raises(ArgumentError) { empty_policy_class { filter :name, if: :admin? } }
    assert_match(/unknown filter options: if/, error.message)

    # In an attributes_for block they're checked when it runs
    policy = empty_policy_class { attributes_for(-> { 1 }) { filter :name, on: :destroy } }
    assert_raises(ArgumentError) { policy_for(policy).filter_params(nil, permitted) }
  end

  test 'Policy::Record#filter_params gives the params as they are without a Policy' do
    record_policy = StandardAPI::Policy::Record.new(ApplicationController.new, Property, nil, nil)
    params = permitted(name: 'Hancock')
    assert_same params, record_policy.filter_params(params)
  end

  test 'POST create writes what the filters leave, after the permits and assigns' do
    policy = Class.new(PropertyPolicy) do
      assign :build_type, with: -> { 'brick' }
      filter do |params|
        params[:description] = "#{params[:name]} in #{params[:build_type]}"
        params.delete(:size)
      end
    end

    with_model_policy(Property, policy) do
      post properties_path, params: { property: { name: 'Hancock', size: 10, build_type: 'metal' } }, as: :json
    end

    assert_response :created
    property = Property.last
    assert_equal 'Hancock in brick', property.description
    assert_nil property.size
  end

  test 'POST create without params still runs the filters' do
    with_model_policy(Property, Class.new(PropertyPolicy) { filter { |params| params[:name] = 'Hancock' } }) do
      post properties_path, params: {}, as: :json
    end

    assert_response :created
    assert_equal 'Hancock', Property.last.name
  end

  test 'a filter raising UnpermittedParameters is a 400 and writes nothing' do
    policy = Class.new(PropertyPolicy) do
      filter do |params|
        raise StandardAPI::UnpermittedParameters.new([{ property: ['active'] }]) if params[:active] && !admin?
      end

      private

      def admin? = false
    end

    assert_no_difference 'Property.count' do
      with_model_policy(Property, policy) do
        post properties_path, params: { property: { name: 'Hancock', active: true } }, as: :json
      end
    end

    assert_response :bad_request
    assert_match(/found unpermitted parameter: \{.*property.*active/, response.body)
  end

  test 'PATCH update runs only the filters on update, with record the record being updated' do
    property = create(:property, name: 'Hancock', description: 'Tall')
    policy = Class.new(PropertyPolicy) do
      filter(on: :create) { |params| params[:description] = 'Created' }
      filter(on: :update) { |params| params[:description] = "Was #{record.name_was}" }
    end

    with_model_policy(Property, policy) do
      patch property_path(property), params: { property: { name: 'Sears' } }, as: :json
    end

    assert_response :ok
    property.reload
    assert_equal 'Sears', property.name
    assert_equal 'Was Hancock', property.description
  end

  test "nested records run their own Policy's filters, or those of the writable policy" do
    account = create(:account, name: 'A Co.')
    property = create(:property, accounts: [account])
    account_policy = Class.new(AccountPolicy) do
      filter(on: :update) { |params| params[:name] = "#{params[:name]} (updated)" }
      filter(on: :create) { |params| params[:name] = "#{params[:name]} (new)" }
    end
    policy = Class.new(PropertyPolicy) { association :accounts, writable: { policy: account_policy } }
    # Not run, as the writable policy takes its place
    own_policy = Class.new(AccountPolicy) { filter { |params| params[:name] = 'Own' } }

    with_model_policy(Account, own_policy) do
      with_model_policy(Property, policy) do
        patch property_path(property), params: { property: { accounts: [
          { id: account.id, name: 'B Co.' },
          { name: 'C Co.' }
        ] } }, as: :json
      end
    end

    assert_response :ok
    assert_equal 'B Co. (updated)', account.reload.name
    assert_equal ['B Co. (updated)', 'C Co. (new)'], property.accounts.reload.map(&:name).sort
  end

  test "nested records without a writable policy run their own model's" do
    property = create(:property)
    account_policy = Class.new(AccountPolicy) { filter { |params| params[:name] = params[:name].upcase } }

    with_model_policy(Account, account_policy) do
      patch property_path(property), params: { property: { accounts: [{ name: 'c co.' }] } }, as: :json
    end

    assert_response :ok
    assert_equal ['C CO.'], property.accounts.reload.map(&:name)
  end

end
