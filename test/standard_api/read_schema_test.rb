require 'standard_api/test_helper'

class ReadSchemaTest < ActionDispatch::IntegrationTest

  def read_schema(path, **params)
    get path, params: params
    assert_response :ok
    JSON(response.body)
  end

  test 'Controller#read_schema.json lists every column' do
    schema = read_schema(read_schema_properties_path(format: 'json'))

    assert_equal 'https://json-schema.org/draft/2020-12/schema', schema['$schema']
    assert_equal Property.column_names + ['errors'], schema['properties'].keys
    assert_equal Property.column_names, schema['required']
    assert_equal false, schema['additionalProperties']
  end

  test 'Controller#read_schema.json types, as rendered' do
    properties = read_schema(read_schema_properties_path(format: 'json'))['properties']

    assert_equal 'integer', properties.dig('id', 'type')
    assert_equal ['string', 'null'], properties.dig('name', 'type')
    # BigDecimal renders as a String
    assert_equal ['string', 'null'], properties.dig('size', 'type')
    assert_equal 'date-time', properties.dig('created_at', 'format')
  end

  test 'Controller#read_schema.json enum' do
    properties = read_schema(read_schema_documents_path(format: 'json'))['properties']

    assert_equal 'string', properties.dig('level', 'type')
    assert_equal ['public', 'secret'], properties.dig('level', 'enum')
  end

  test 'Controller#read_schema.json binary' do
    properties = read_schema(read_schema_references_path(format: 'json'))['properties']

    assert_equal 'base16', properties.dig('sha', 'contentEncoding')
    # A custom type is rendered however it casts
    assert_equal({}, properties['custom_binary'])
  end

  test 'Controller#read_schema.json with excludes requires nothing' do
    schema = read_schema(read_schema_cameras_path(format: 'json'))

    # Left out rather than empty
    assert_not schema.key?('required')
    # CameraACL#excludes hides make from hidden cameras only
    assert_includes schema['properties'].keys, 'make'
  end

  test 'Controller#read_schema.json leaves out what ApplicationHelper#excludes excludes' do
    ApplicationHelper.module_eval do
      def excludes
        { account: [:email] }
      end
    end

    schema = read_schema(read_schema_account_path(format: 'json'))
    assert_not_includes schema['properties'].keys, 'email'
    assert_includes schema['properties'].keys, 'name'
  ensure
    ApplicationHelper.module_eval { remove_method :excludes }
  end

  test 'Controller#read_schema_for is public and gives what read_schema.json renders' do
    schema = read_schema(read_schema_properties_path(format: 'json'), include: 'landlord')

    assert_equal schema, controller.read_schema_for(Property, controller.send(:includes)).as_json
  end

  test 'Controller#read_schema.json include has_many' do
    PropertiesController.any_instance.stubs(:property_includes).returns([:accounts])
    schema = read_schema(read_schema_properties_path(format: 'json'), include: 'accounts')

    assert_equal 'array', schema.dig('properties', 'accounts', 'type')
    assert_equal ['string', 'null'], schema.dig('properties', 'accounts', 'items', 'properties', 'email', 'type')
    assert_includes schema['required'], 'accounts'
  end

  test 'Controller#read_schema.json include has_one' do
    schema = read_schema(read_schema_properties_path(format: 'json'), include: 'landlord')

    assert_equal ['object', 'null'], schema.dig('properties', 'landlord', 'type')
    assert_equal Account.column_names + ['errors'], schema.dig('properties', 'landlord', 'properties').keys
  end

  test 'Controller#read_schema.json an included association is nullable unless its presence is validated' do
    # Camera's belongs_to :photo is optional
    schema = read_schema(read_schema_cameras_path(format: 'json'), include: 'photo')
    assert_equal ['object', 'null'], schema.dig('properties', 'photo', 'type')

    # A required belongs_to (optional: false, or belongs_to_required_by_default)
    # validates its presence
    Camera.stubs(:validators_on).returns([])
    Camera.stubs(:validators_on).with(:photo).returns([ActiveRecord::Validations::PresenceValidator.new(attributes: [:photo])])
    schema = read_schema(read_schema_cameras_path(format: 'json'), include: 'photo')
    assert_equal 'object', schema.dig('properties', 'photo', 'type')
  end

  test 'Controller#read_schema.json include of a method' do
    schema = read_schema(read_schema_properties_path(format: 'json'), include: 'english_name')

    assert_equal({}, schema.dig('properties', 'english_name'))
  end

  test 'Controller#read_schema.json include not permitted' do
    get read_schema_properties_path(format: 'json'), params: { include: 'agree_to_terms' }

    assert_response :bad_request
  end

  test 'Controller#read_schema.json with a custom partial' do
    schema = read_schema(read_schema_photos_path(format: 'json'))

    assert_equal 'object', schema['type']
    assert_equal 'Rendered by photos/photo', schema['description']
    assert_nil schema['properties']
  end

  test 'Controller#read_schema.json describes attributes without a column' do
    schema = read_schema(read_schema_documents_path(format: 'json'))

    assert_equal ['integer', 'null'], schema.dig('properties', 'page_count', 'type')
    # A partial select may leave it out
    assert_not_includes schema['required'], 'page_count'
    assert_includes schema['required'], 'level'
  end

  test 'Controller#show.json with an attribute without a column validates against Controller#read_schema.json' do
    document = create(:document)
    schemer = JSONSchemer.schema(read_schema(read_schema_documents_path(format: 'json')))

    get document_path(document, format: 'json')
    assert_response :ok
    assert_equal 1, JSON(response.body)['page_count']
    assert_empty schemer.validate(JSON(response.body)).map { |e| e['error'] }
  end

  test 'Controller#read_schema.json description from the ACL schemas' do
    schema = read_schema(read_schema_cameras_path(format: 'json'))

    assert_equal 'The manufacturer', schema.dig('properties', 'make', 'description')
  end

  test 'Controller#read_schema.json describes a definition the ACL schemas adds' do
    ApplicationController.define_method(:account_schemas) do |default_schema|
      default_schema + [{ name: 'nickname', type: 'string' }]
    end
    ApplicationController.send(:private, :account_schemas)
    schema = read_schema(read_schema_account_path(format: 'json'))

    # null defaults to true, and without a column it isn't required
    assert_equal({ 'type' => ['string', 'null'] }, schema.dig('properties', 'nickname'))
    assert_not_includes schema['required'], 'nickname'
    assert_equal Account.column_names + ['nickname', 'errors'], schema['properties'].keys
  ensure
    ApplicationController.send(:remove_method, :account_schemas)
  end

  test 'Controller#read_schema.json leaves out a definition the ACL schemas drops' do
    ApplicationController.define_method(:property_schemas) do |default_schema|
      default_schema.select { |s| ['id', 'name'].include?(s[:name]) }
    end
    ApplicationController.send(:private, :property_schemas)
    schema = read_schema(read_schema_properties_path(format: 'json'))

    assert_equal ['id', 'name', 'errors'], schema['properties'].keys
    assert_equal ['id', 'name'], schema['required']
  ensure
    ApplicationController.send(:remove_method, :property_schemas)
  end

  test 'Controller#read_schema.json the ACL schemas apply to included models' do
    ApplicationController.define_method(:account_schemas) do |default_schema|
      default_schema + [{ name: 'nickname', type: 'string' }]
    end
    ApplicationController.send(:private, :account_schemas)
    schema = read_schema(read_schema_properties_path(format: 'json'), include: 'landlord')

    assert_equal ['string', 'null'], schema.dig('properties', 'landlord', 'properties', 'nickname', 'type')
  ensure
    ApplicationController.send(:remove_method, :account_schemas)
  end

  test 'Controller#read_schema.json is a valid JSON Schema' do
    PropertiesController.any_instance.stubs(:property_includes).returns([:accounts, :landlord])
    schema = read_schema(read_schema_properties_path(format: 'json'), include: { accounts: true, landlord: true })

    assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).map { |e| e['error'] }.join("\n")
  end

  test 'Controller#show.json validates against Controller#read_schema.json' do
    PropertiesController.any_instance.stubs(:property_includes).returns([:accounts, :landlord])
    property = create(:property, accounts: [create(:account)], landlord: create(:account))
    includes = { accounts: true, landlord: true }
    schemer = JSONSchemer.schema(read_schema(read_schema_properties_path(format: 'json'), include: includes))

    get property_path(property, format: 'json'), params: { include: includes }
    assert_response :ok

    errors = schemer.validate(JSON(response.body)).map { |e| e['error'] }
    assert_empty errors
  end

  test 'records of each resource validate against their read_schema.json' do
    property = create(:property, photos: [create(:photo)])
    pages = {
      property_path(property, format: 'json', include: { photos: true, landlord: true }) => read_schema_properties_path(format: 'json', include: { photos: true, landlord: true }),
      photo_path(property.photos.first, format: 'json') => read_schema_photos_path(format: 'json'),
      document_path(create(:document), format: 'json') => read_schema_documents_path(format: 'json'),
      reference_path(create(:reference), format: 'json') => read_schema_references_path(format: 'json'),
      camera_path(create(:camera), format: 'json') => read_schema_cameras_path(format: 'json')
    }

    # json_schemer only decodes base64 itself
    encodings = { 'base16' => ->(value) { value.match?(/\A(\h\h)*\z/) ? [true, [value].pack('H*')] : [false, nil] } }

    pages.each do |record_path, schema_path|
      get schema_path
      assert_response :ok
      schema = JSONSchemer.schema(JSON(response.body), content_encodings: encodings)
      get record_path
      assert_response :ok

      errors = schema.validate(JSON(response.body)).map { |e| "#{e['data_pointer']}: #{e['type']}" }
      assert_empty errors, "#{record_path} doesn't validate against #{schema_path}"
    end
  end

  test 'Controller#index.json records validate against Controller#read_schema.json' do
    create(:property)
    create(:property).update_columns(name: nil, description: nil, size: nil, active: nil)
    schemer = JSONSchemer.schema(read_schema(read_schema_properties_path(format: 'json')))

    get properties_path(format: 'json'), params: { limit: 10 }
    assert_response :ok

    JSON(response.body).each do |record|
      assert_empty schemer.validate(record).map { |e| e['error'] }
    end
  end

end
