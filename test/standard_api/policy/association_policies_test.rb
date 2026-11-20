require 'standard_api/test_helper'

# An association whose policy: picks a Policy per record lists the others it
# can give with policies:, and what can be included, filtered and ordered of
# its records is checked against all of them.
class PolicyAssociationPoliciesTest < ActionDispatch::IntegrationTest

  def with_policies(policies)
    merged = ApplicationController.standard_api_policies.merge(policies)
    ApplicationController.stubs(:standard_api_policies).returns(merged)
    yield
  ensure
    ApplicationController.unstub(:standard_api_policies)
  end

  # What a property's accounts render with: +full+ for a model and most
  # records, +narrow+ for the accounts of a property named Narrowed
  def full
    @full ||= Class.new(StandardAPI::Policy) do
      attributes :id, :name, :email
      attribute :name, filterable: true, orderable: true
      attribute :email, filterable: true
      association :photos
    end
  end

  def narrow
    @narrow ||= Class.new(StandardAPI::Policy) do
      attributes :id, :name
      attribute :name, filterable: true
      association :property
    end
  end

  def property_policy(policies: [narrow])
    full = self.full
    narrow = self.narrow
    Class.new(PropertyPolicy) do
      association :accounts, policy: -> { record&.name == 'Narrowed' ? narrow : full }, policies: policies
    end
  end

  def show_property(property, include)
    get "/properties/#{property.id}", params: { include: include }, as: :json
    JSON(response.body) if response.status == 200
  end

  def properties
    narrowed = create(:property, name: 'Narrowed')
    whole = create(:property, name: 'Whole')
    [narrowed, whole].each do |property|
      account = create(:account, property: property, name: 'Lord', email: 'lord@example.com')
      create(:photo, account: account)
    end
    [narrowed, whole]
  end

  test 'each record renders with the Policy its policy: gives it' do
    narrowed, whole = properties

    with_policies('property' => property_policy) do
      assert_equal %w(id name), show_property(narrowed, [:accounts])['accounts'][0].keys.sort
      assert_equal %w(email id name), show_property(whole, [:accounts])['accounts'][0].keys.sort
    end
  end

  test 'an include is permitted if one of the Policies declares it, and renders where its own does' do
    narrowed, whole = properties

    with_policies('property' => property_policy) do
      # Only full declares photos
      assert_not show_property(narrowed, { accounts: { photos: true } })['accounts'][0].key?('photos')
      assert_equal 1, show_property(whole, { accounts: { photos: true } })['accounts'][0]['photos'].size

      # Only narrow declares property
      assert_equal narrowed.id, show_property(narrowed, { accounts: { property: true } })['accounts'][0]['property']['id']
      assert_not show_property(whole, { accounts: { property: true } })['accounts'][0].key?('property')

      # Neither declares subject
      show_property(whole, { accounts: { subject: true } })
      assert_response :bad_request
    end
  end

  test 'a where, order or when on the included records has to be permitted by every Policy' do
    _narrowed, whole = properties

    with_policies('property' => property_policy) do
      assert_equal 1, show_property(whole, { accounts: { where: { name: 'Lord' } } })['accounts'].size

      # full permits these, and narrow doesn't
      show_property(whole, { accounts: { where: { email: 'lord@example.com' } } })
      assert_response :bad_request
      show_property(whole, { accounts: { order: { name: :asc } } })
      assert_response :bad_request
      show_property(whole, { accounts: { photos: { when: { email: 'lord@example.com' } } } })
      assert_response :bad_request

      show_property(whole, { accounts: { photos: { when: { name: 'Lord' } } } })
      assert_response :ok
    end
  end

  test "a Policy policy: gives a record that policies: doesn't list raises" do
    narrowed, whole = properties

    with_policies('property' => property_policy(policies: [])) do
      assert_equal %w(email id name), show_property(whole, [:accounts])['accounts'][0].keys.sort

      error = assert_raises(ActionView::Template::Error) { show_property(narrowed, [:accounts]) }
      assert_instance_of ArgumentError, error.cause
      assert_match(/policy: of association accounts of Property gave .* for a record, but for a model .*; list the others it gives with policies:/, error.cause.message)
    end
  end

  test 'declared_includes lists the Policies an association can render with' do
    with_policies('property' => property_policy) do
      declared = PropertiesController.new.send(:model_policy, Property).declared_includes
      assert_equal full, declared[:accounts][:policy]
      assert_equal [full, narrow], declared[:accounts][:policies]
      assert_equal [nil], declared[:landlord][:policies]
    end
  end

  test 'policies: takes Policy classes, with a policy: given as a Proc or method name' do
    full = self.full
    narrow = self.narrow
    assert_raises(ArgumentError) { Class.new(StandardAPI::Policy) { association :accounts, policies: [narrow] } }
    assert_raises(ArgumentError) { Class.new(StandardAPI::Policy) { association :accounts, policy: full, policies: [narrow] } }
    assert_raises(ArgumentError) { Class.new(StandardAPI::Policy) { association :accounts, policy: -> { nil }, policies: [Object] } }
    assert_raises(ArgumentError) { Class.new(StandardAPI::Policy) { association :accounts, policy: -> { nil }, policies: narrow } }
    Class.new(StandardAPI::Policy) { association :accounts, policy: :accounts_policy, policies: [narrow] }

    # Declared in attributes_for, it's checked when built
    policy = Class.new(StandardAPI::Policy) { attributes_for(-> { record&.id }) { association :accounts, policies: [] } }
    assert_raises(ArgumentError) { policy.new(PropertiesController.new, Property).send(:builder_for, create(:property)) }
  end

end
