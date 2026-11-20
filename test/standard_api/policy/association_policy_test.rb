require 'standard_api/test_helper'

# An association's policy: given as a Proc or a method name is chosen once a
# request, so what's checked of an include, described and rendered all use
# the same Policy
class PolicyAssociationPolicyTest < ActionDispatch::IntegrationTest

  # Render with +policies+, a model's prefix to its Policy, for the length of
  # the block
  def with_policies(policies)
    merged = ApplicationController.standard_api_policies.merge(policies)
    ApplicationController.stubs(:standard_api_policies).returns(merged)
    yield
  ensure
    ApplicationController.unstub(:standard_api_policies)
  end

  # Its accounts' email can be filtered on and their photos included
  def wide_policy
    Class.new(AccountPolicy) { attribute :email, filterable: true }
  end

  # Its accounts render only an id and name
  def narrow_policy
    Class.new(StandardAPI::Policy) { attributes :id, :name }
  end

  def property_policy(&block)
    Class.new(PropertyPolicy, &block)
  end

  # Headers of a requester the accounts' Policy is wide for
  def wide_requester = { 'X-Wide' => '1' }

  test "a policy: Proc that reads record raises" do
    property = create(:property, name: 'Narrowed', accounts: [create(:account)])
    narrow = narrow_policy
    policy = property_policy { association :accounts, policy: -> { narrow if record&.name == 'Narrowed' } }

    with_policies('property' => policy) do
      error = assert_raises(ArgumentError) do
        get "/properties/#{property.id}", params: { include: [:accounts] }, as: :json
      end
      assert_match(/policy: of association accounts is chosen once a request/, error.message)
      assert_match(/if: and unless:/, error.message)

      assert_raises(ArgumentError) do
        get read_schema_properties_path(format: 'json'), params: { include: [:accounts] }
      end
      assert_raises(ArgumentError) { get query_schema_properties_path(format: 'json') }
    end
  end

  test "a policy: method that reads record raises" do
    narrow = narrow_policy
    policy = property_policy do
      association :accounts, policy: :accounts_policy
      define_method(:accounts_policy) { narrow if record&.name == 'Narrowed' }
      private :accounts_policy
    end

    with_policies('property' => policy) do
      error = assert_raises(ArgumentError) { get query_schema_properties_path(format: 'json') }
      assert_match(/chosen once a request/, error.message)
    end
  end

  # Asserts the Policy +policy+ gives the accounts of a property is +wide+
  # for a request with the X-Wide header and +narrow+ otherwise, when
  # checking includes, describing them and rendering them
  def assert_chosen_per_requester(policy)
    property = create(:property)
    account = create(:account, property: property, name: 'Ansel', email: 'ansel@example.com')
    create(:photo, account: account)

    with_policies('property' => policy) do
      # Nested includes and filters are checked against the Policy chosen
      get "/properties/#{property.id}", params: { include: { accounts: [:photos] } }, headers: wide_requester, as: :json
      assert_response :ok
      assert_equal 1, JSON(response.body)['accounts'].first['photos'].size
      get "/properties/#{property.id}", params: { include: { accounts: [:photos] } }, as: :json
      assert_response :bad_request

      get "/properties/#{property.id}", params: { include: { accounts: { where: { email: 'nobody@example.com' } } } }, headers: wide_requester, as: :json
      assert_response :ok
      assert_equal [], JSON(response.body)['accounts']
      get "/properties/#{property.id}", params: { include: { accounts: { where: { email: 'nobody@example.com' } } } }, as: :json
      assert_response :bad_request

      # And render with it
      get "/properties/#{property.id}", params: { include: [:accounts] }, headers: wide_requester, as: :json
      assert_equal 'ansel@example.com', JSON(response.body)['accounts'].first['email']
      get "/properties/#{property.id}", params: { include: [:accounts] }, as: :json
      assert_equal %w[id name], JSON(response.body)['accounts'].first.keys.sort

      # The read schema describes what renders
      get read_schema_properties_path(format: 'json'), params: { include: [:accounts] }, headers: wide_requester
      assert_includes JSON(response.body).dig('properties', 'accounts', 'items', 'properties').keys, 'email'
      get read_schema_properties_path(format: 'json'), params: { include: [:accounts] }
      assert_equal %w[errors id name], JSON(response.body).dig('properties', 'accounts', 'items', 'properties').keys.sort

      # The query schema what's permitted
      get query_schema_properties_path(format: 'json'), headers: wide_requester
      schemer = JSONSchemer.schema(JSON(response.body))
      assert schemer.valid?({ 'limit' => 1, 'include' => { 'accounts' => { 'photos' => true } } })
      get query_schema_properties_path(format: 'json')
      schemer = JSONSchemer.schema(JSON(response.body))
      assert_not schemer.valid?({ 'limit' => 1, 'include' => { 'accounts' => { 'photos' => true } } })
    end
  end

  test "a policy: Proc is chosen by the requester" do
    wide, narrow = wide_policy, narrow_policy
    assert_chosen_per_requester(property_policy do
      association :accounts, policy: -> { request.headers['X-Wide'] == '1' ? wide : narrow }
    end)
  end

  test "a policy: method is chosen by the requester" do
    wide, narrow = wide_policy, narrow_policy
    assert_chosen_per_requester(property_policy do
      association :accounts, policy: :accounts_policy
      define_method(:accounts_policy) { request.headers['X-Wide'] == '1' ? wide : narrow }
      private :accounts_policy
    end)
  end

  test "a policy: Proc runs once a request" do
    calls = 0
    narrow = narrow_policy
    policy = property_policy { association :accounts, policy: -> { calls += 1; narrow } }
    property = create(:property, accounts: [create(:account), create(:account)])

    with_policies('property' => policy) do
      get "/properties/#{property.id}", params: { include: [:accounts] }, as: :json
      assert_response :ok
      assert_equal 1, calls
    end
  end

end
