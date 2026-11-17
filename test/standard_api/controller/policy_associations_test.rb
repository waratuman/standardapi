require 'standard_api/test_helper'

class ControllerPolicyAssociationsTest < ActionDispatch::IntegrationTest

  # Render with +policies+, a model's prefix to its Policy, for the length of
  # the block
  def with_policies(policies)
    merged = ApplicationController.standard_api_policies.merge(policies)
    ApplicationController.stubs(:standard_api_policies).returns(merged)
    yield
  ensure
    ApplicationController.unstub(:standard_api_policies)
  end

  def property_policy(&block)
    Class.new(PropertyPolicy, &block)
  end

  def name_policy
    Class.new(StandardAPI::Policy) { attributes :id, :name }
  end

  def show_property(property, include)
    get "/properties/#{property.id}", params: { include: include }, as: :json
    assert_response :ok
    JSON(response.body)
  end

  test "an association the Policy doesn't declare can't be included" do
    property = create(:property, landlord: create(:account))

    with_policies('property' => property_policy { remove :landlord }) do
      get "/properties/#{property.id}", params: { include: [:landlord] }, as: :json
      assert_response :bad_request

      get read_schema_properties_path(format: 'json'), params: { include: [:landlord] }
      assert_response :bad_request
    end
    assert show_property(property, [:landlord]).key?('landlord')
  end

  test 'an association renders only when the include param asks for it' do
    property = create(:property, landlord: create(:account))

    assert_not show_property(property, []).key?('landlord')
    assert show_property(property, [:landlord]).key?('landlord')
  end

  test 'if and unless hide an association per record' do
    shown = create(:property, name: 'Shown', landlord: create(:account))
    hidden = create(:property, name: 'Hidden', landlord: create(:account))

    policy = property_policy { association :landlord, if: -> { record&.name != 'Hidden' } }
    with_policies('property' => policy) do
      assert show_property(shown, [:landlord]).key?('landlord')
      assert_not show_property(hidden, [:landlord]).key?('landlord')
    end

    policy = property_policy { association :landlord, unless: -> { record&.name == 'Hidden' } }
    with_policies('property' => policy) do
      assert show_property(shown, [:landlord]).key?('landlord')
      assert_not show_property(hidden, [:landlord]).key?('landlord')
    end
  end

  test 'a conditional association makes the Policy vary by requester' do
    assert_not PropertyPolicy.varies_by_requester?
    assert property_policy { association :landlord, if: -> { true } }.varies_by_requester?
    assert property_policy { association :landlord, policy: -> { nil } }.varies_by_requester?

    varying = Class.new(StandardAPI::Policy) { attribute :name, if: -> { true } }
    narrowing = property_policy { association :landlord, policy: varying }
    assert narrowing.varies_by_requester?
    assert_not property_policy { association :landlord, policy: Class.new(StandardAPI::Policy) }.varies_by_requester?
  end

  test 'policy renders the included records with what it declares' do
    property = create(:property, landlord: create(:account, name: 'Lord', email: 'lord@example.com'))

    policy = property_policy { association :landlord, policy: Class.new(StandardAPI::Policy) { attributes :id, :name } }
    with_policies('property' => policy) do
      landlord = show_property(property, [:landlord])['landlord']
      assert_equal %w[id name], landlord.keys.sort
      assert_equal 'Lord', landlord['name']
    end
  end

  test "policy takes the place of the included model's own Policy" do
    property = create(:property, landlord: create(:account, name: 'Lord'))

    account = Class.new(AccountPolicy) { remove :name }
    policy = property_policy { association :landlord, policy: Class.new(StandardAPI::Policy) { attributes :id, :name } }
    with_policies('property' => policy, 'account' => account) do
      assert_equal({ 'id' => property.landlord.id, 'name' => 'Lord' }, show_property(property, [:landlord])['landlord'])
    end
  end

  test "a policy inheriting from the included model's Policy keeps what it hides" do
    property = create(:property, landlord: create(:account, name: 'Lord', email: 'lord@example.com'))

    account = Class.new(AccountPolicy) { remove :name }
    without_email = Class.new(account) { remove :email }
    with_policies('property' => property_policy { association :landlord, policy: without_email }, 'account' => account) do
      landlord = show_property(property, [:landlord])['landlord']
      assert_not landlord.key?('name')
      assert_not landlord.key?('email')
      assert landlord.key?('id')
    end
  end

  test "an included record's values come from the policy it renders with" do
    property = create(:property, landlord: create(:account, name: 'Lord'))

    account = Class.new(AccountPolicy) { attribute :name, value: -> { 'Own' } }
    through = Class.new(StandardAPI::Policy) { attributes :id; attribute :name, value: -> { 'Through' } }
    with_policies('property' => property_policy { association :landlord, policy: through }, 'account' => account) do
      assert_equal 'Through', show_property(property, [:landlord])['landlord']['name']
    end
    with_policies('account' => account) do
      assert_equal 'Own', show_property(property, [:landlord])['landlord']['name']
    end
  end

  test 'policy decides the associations of the included records too' do
    property = create(:property)
    # A nil property_cached_at fails association_cache_key, apart from this
    create(:account, property: property, property_cached_at: Time.now)
    assert show_property(property, { landlord: { property: true } })['landlord'].key?('property')

    policy = property_policy { association :landlord, policy: Class.new(StandardAPI::Policy) { attributes :id, :name } }
    with_policies('property' => policy) do
      get "/properties/#{property.id}", params: { include: { landlord: { property: true } } }, as: :json
      assert_response :bad_request
    end
  end

  test 'policy renders records a custom partial renders, through record_policy' do
    property = create(:property, photos: [create(:photo, format: 'jpg')])

    policy = property_policy { association :photos, policy: Class.new(StandardAPI::Policy) { attributes :id } }
    with_policies('property' => policy) do
      photo = show_property(property, [:photos])['photos'].first
      assert_equal %w[id template], photo.keys.sort
    end
  end

  test 'policy given as a Proc is chosen per including record' do
    narrowed = create(:property, name: 'Narrowed', landlord: create(:account, email: 'a@example.com'))
    whole = create(:property, name: 'Whole', landlord: create(:account, email: 'b@example.com'))

    narrow = Class.new(StandardAPI::Policy) { attributes :id, :name }
    policy = property_policy { association :landlord, policy: -> { narrow if record&.name == 'Narrowed' } }
    with_policies('property' => policy) do
      assert_not show_property(narrowed, [:landlord])['landlord'].key?('email')
      assert_equal 'b@example.com', show_property(whole, [:landlord])['landlord']['email']
    end
  end

  test 'policy renders a polymorphic association whatever model it is' do
    property = create(:property, name: 'Subject')
    account = create(:account, subject: property)

    narrow = Class.new(StandardAPI::Policy) { attributes :id, :name }
    with_policies('account' => Class.new(AccountPolicy) { association :subject, policy: narrow }) do
      get '/accounts', params: { include: [:subject], limit: 10, where: { id: account.id } }, as: :json
      assert_response :ok
      assert_equal({ 'id' => property.id, 'name' => 'Subject' }, JSON(response.body).first['subject'])
    end
  end

  test 'the read policy describes an included record as its policy renders it' do
    narrow = Class.new(StandardAPI::Policy) { attributes :id, :name }
    with_policies('property' => property_policy { association :landlord, policy: narrow }) do
      get read_schema_properties_path(format: 'json'), params: { include: [:landlord] }
      landlord = JSON(response.body).dig('properties', 'landlord')
      assert_equal %w[errors id name], landlord['properties'].keys.sort
      assert_equal %w[id name], landlord['required'].sort
    end
  end

  test 'an attributes_for block can declare associations' do
    property = create(:property, name: 'Keyed', landlord: create(:account))

    # What can be included is what it declares for the model, so key it on
    # something the request has, not the record
    policy = property_policy do
      remove :landlord
      attributes_for(-> { params[:keyed] }) { |keyed| association :landlord if keyed == '1' }
    end
    with_policies('property' => policy) do
      get "/properties/#{property.id}", params: { include: [:landlord], keyed: '1' }, as: :json
      assert JSON(response.body).key?('landlord')

      get "/properties/#{property.id}", params: { include: [:landlord] }, as: :json
      assert_response :bad_request
    end
  end

  test 'an association with an unknown option or a policy that is not a Policy raises' do
    assert_raises(ArgumentError) { property_policy { association :landlord, sideways: true }.new(nil, Property).association?(nil, :landlord) }
    assert_raises(ArgumentError) { property_policy { association :landlord, policy: Account } }
  end

end
