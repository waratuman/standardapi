require 'standard_api/test_helper'

class ControllerSchemaAssociationsTest < ActionDispatch::IntegrationTest

  # Render with +schemas+, a model's prefix to its Schema, for the length of
  # the block
  def with_schemas(schemas)
    merged = ApplicationController.standard_api_schemas.merge(schemas)
    ApplicationController.stubs(:standard_api_schemas).returns(merged)
    yield
  ensure
    ApplicationController.unstub(:standard_api_schemas)
  end

  def property_schema(&block)
    Class.new(PropertySchema, &block)
  end

  def name_schema
    Class.new(StandardAPI::Schema) { attributes :id, :name }
  end

  def show_property(property, include)
    get "/properties/#{property.id}", params: { include: include }, as: :json
    assert_response :ok
    JSON(response.body)
  end

  test 'an association the Schema does not declare is not rendered' do
    property = create(:property, landlord: create(:account))

    with_schemas('property' => property_schema { remove :landlord }) do
      assert_not show_property(property, [:landlord]).key?('landlord')
    end
    assert show_property(property, [:landlord]).key?('landlord')
  end

  test 'an association a Schema does not declare is left out of the read schema' do
    with_schemas('property' => property_schema { remove :landlord }) do
      get read_schema_properties_path(format: 'json'), params: { include: [:landlord] }
      assert_not JSON(response.body)['properties'].key?('landlord')
    end
  end

  test 'if and unless hide an association per record' do
    shown = create(:property, name: 'Shown', landlord: create(:account))
    hidden = create(:property, name: 'Hidden', landlord: create(:account))

    schema = property_schema { association :landlord, if: -> { record&.name != 'Hidden' } }
    with_schemas('property' => schema) do
      assert show_property(shown, [:landlord]).key?('landlord')
      assert_not show_property(hidden, [:landlord]).key?('landlord')
    end

    schema = property_schema { association :landlord, unless: -> { record&.name == 'Hidden' } }
    with_schemas('property' => schema) do
      assert show_property(shown, [:landlord]).key?('landlord')
      assert_not show_property(hidden, [:landlord]).key?('landlord')
    end
  end

  test 'a conditional association makes the Schema vary by requester' do
    assert_not PropertySchema.varies_by_requester?
    assert property_schema { association :landlord, if: -> { true } }.varies_by_requester?
    assert property_schema { association :landlord, schema: -> { nil } }.varies_by_requester?

    varying = Class.new(StandardAPI::Schema) { attribute :name, if: -> { true } }
    narrowing = property_schema { association :landlord, schema: varying }
    assert narrowing.varies_by_requester?
    assert_not property_schema { association :landlord, schema: Class.new(StandardAPI::Schema) }.varies_by_requester?
  end

  test 'schema narrows the included records to what it declares' do
    property = create(:property, landlord: create(:account, name: 'Lord', email: 'lord@example.com'))

    schema = property_schema { association :landlord, schema: Class.new(StandardAPI::Schema) { attributes :id, :name } }
    with_schemas('property' => schema) do
      landlord = show_property(property, [:landlord])['landlord']
      assert_equal %w[id name], landlord.keys.sort
      assert_equal 'Lord', landlord['name']
    end
  end

  test "schema can't show what the included model's own Schema hides" do
    property = create(:property, landlord: create(:account, name: 'Lord'))

    account = Class.new(AccountSchema) { remove :name }
    schema = property_schema { association :landlord, schema: Class.new(StandardAPI::Schema) { attributes :id, :name } }
    with_schemas('property' => schema, 'account' => account) do
      assert_equal %w[id], show_property(property, [:landlord])['landlord'].keys
    end
  end

  test 'schema narrows the associations of the included records too' do
    property = create(:property)
    # A nil property_cached_at fails association_cache_key, apart from this
    create(:account, property: property, property_cached_at: Time.now)
    assert show_property(property, { landlord: { property: true } })['landlord'].key?('property')

    schema = property_schema { association :landlord, schema: Class.new(StandardAPI::Schema) { attributes :id, :name } }
    with_schemas('property' => schema) do
      assert_not show_property(property, { landlord: { property: true } })['landlord'].key?('property')
    end
  end

  test 'schema narrows records a custom partial renders, through schema_for' do
    property = create(:property, photos: [create(:photo, format: 'jpg')])

    schema = property_schema { association :photos, schema: Class.new(StandardAPI::Schema) { attributes :id } }
    with_schemas('property' => schema) do
      photo = show_property(property, [:photos])['photos'].first
      assert_equal %w[id template], photo.keys.sort
    end
  end

  test 'schema given as a Proc is chosen per including record' do
    narrowed = create(:property, name: 'Narrowed', landlord: create(:account, email: 'a@example.com'))
    whole = create(:property, name: 'Whole', landlord: create(:account, email: 'b@example.com'))

    narrow = Class.new(StandardAPI::Schema) { attributes :id, :name }
    schema = property_schema { association :landlord, schema: -> { narrow if record&.name == 'Narrowed' } }
    with_schemas('property' => schema) do
      assert_not show_property(narrowed, [:landlord])['landlord'].key?('email')
      assert_equal 'b@example.com', show_property(whole, [:landlord])['landlord']['email']
    end
  end

  test 'schema narrows a polymorphic association whatever model it is' do
    property = create(:property, name: 'Subject')
    account = create(:account, subject: property)

    narrow = Class.new(StandardAPI::Schema) { attributes :id, :name }
    with_schemas('account' => Class.new(AccountSchema) { association :subject, schema: narrow }) do
      get '/accounts', params: { include: [:subject], limit: 10, where: { id: account.id } }, as: :json
      assert_response :ok
      assert_equal({ 'id' => property.id, 'name' => 'Subject' }, JSON(response.body).first['subject'])
    end
  end

  test 'the read schema describes an included record as its schema narrows it' do
    narrow = Class.new(StandardAPI::Schema) { attributes :id, :name }
    with_schemas('property' => property_schema { association :landlord, schema: narrow }) do
      get read_schema_properties_path(format: 'json'), params: { include: [:landlord] }
      landlord = JSON(response.body).dig('properties', 'landlord')
      assert_equal %w[errors id name], landlord['properties'].keys.sort
      assert_equal %w[id name], landlord['required'].sort
    end
  end

  test 'an attributes_for block can declare associations' do
    property = create(:property, name: 'Keyed', landlord: create(:account))

    schema = property_schema do
      remove :landlord
      attributes_for(-> { record&.name }) { |name| association :landlord if name == 'Keyed' }
    end
    with_schemas('property' => schema) do
      assert show_property(property, [:landlord]).key?('landlord')
      property.update!(name: 'Other')
      assert_not show_property(property, [:landlord]).key?('landlord')
    end
  end

  test 'an association with an unknown option or a schema that is not a Schema raises' do
    assert_raises(ArgumentError) { property_schema { association :landlord, sideways: true }.new(nil, Property).association?(nil, :landlord) }
    assert_raises(ArgumentError) { property_schema { association :landlord, schema: Account } }
  end

end
