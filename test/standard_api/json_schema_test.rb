require 'standard_api/test_helper'
require 'json_schemer'

class JSONSchemaTest < ActionDispatch::IntegrationTest

  # The JSON Schema of +attribute+ in cameras' json_schema.json, with the
  # +validations+ given to it through the ACL's schemas
  def camera_attribute_schema(attribute, validations)
    ApplicationController.define_method(:camera_schemas) do |default_schema|
      default_schema.map { |s| s[:name] == attribute ? s.merge(validations: validations) : s }
    end
    ApplicationController.send(:private, :camera_schemas)

    get json_schema_cameras_path(format: 'json')
    assert_response :ok
    JSON(response.body).dig('properties', attribute)
  ensure
    ApplicationController.send(:remove_method, :camera_schemas)
  end

  test 'Controller#json_schema.json is a valid JSON Schema' do
    paths = [
      json_schema_properties_path(format: 'json'),
      json_schema_properties_path(format: 'json', include: { photos: true, landlord: true }),
      json_schema_photos_path(format: 'json'),
      json_schema_documents_path(format: 'json'),
      json_schema_references_path(format: 'json'),
      json_schema_cameras_path(format: 'json')
    ]

    paths.each do |path|
      get path
      assert_response :ok
      errors = JSONSchemer.draft202012.validate(JSON(response.body)).map { |e| "#{e['data_pointer']}: #{e['type']}" }
      assert_empty errors, "#{path} isn't a valid JSON Schema"
    end
  end

  test 'Controller#json_schema.json inclusion validations' do
    inclusion = ->(values) { [{ kind: :inclusion, options: { in: values } }] }

    assert_equal %w[a b], camera_attribute_schema('make', inclusion.(%w[a b]))['enum']
    assert_equal({ 'type' => 'integer', 'minimum' => 1, 'maximum' => 10 }, camera_attribute_schema('photo_id', inclusion.(1..10)))
    assert_equal({ 'type' => 'integer', 'minimum' => 1, 'exclusiveMaximum' => 10 }, camera_attribute_schema('photo_id', inclusion.(1...10)))
    assert_equal({ 'type' => 'integer', 'minimum' => 5 }, camera_attribute_schema('photo_id', inclusion.(5..)))
    # JSON Schema can't describe a Range of Strings or a Proc
    assert_equal({ 'type' => 'string' }, camera_attribute_schema('make', inclusion.('a'..'z')))
    assert_equal({ 'type' => 'string' }, camera_attribute_schema('make', inclusion.(->(_) { %w[a] })))
  end

  test 'Controller#json_schema.json format validations' do
    format = ->(with) { [{ kind: :format, options: { with: with } }] }

    assert_equal '\\d{3}-\\d{4}', camera_attribute_schema('make', format.(/\d{3}-\d{4}/))['pattern']
    assert_equal '(?:a|b)c', camera_attribute_schema('make', format.(/(?:a|b)c/))['pattern']
    # JavaScript doesn't read these the way Ruby does
    [/\A\d+\z/, /(?i)abc/, /abc/i, /\h+/, ->(_) { /x/ }].each do |with|
      assert_equal({ 'type' => 'string' }, camera_attribute_schema('make', format.(with)), with.inspect)
    end
  end

  test 'Controller#json_schema.json' do
    get json_schema_cameras_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema.has_key?('properties')
    assert_equal true, schema['required'].include?('make')
  end

  test 'Controller#json_schema.json description from the ACL schemas' do
    get json_schema_cameras_path(format: 'json')

    assert_equal 'The manufacturer', JSON(response.body).dig('properties', 'make', 'description')
  end

  test 'Controller#json_schema.json table description' do
    skip "Adapter does not support comments on databases" if !mariadb? && !postgres?

    get json_schema_documents_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 'I <3 Documents', schema['description']
  end
  
  test 'Controller#json_schema.json default' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 2, schema.dig('properties', 'numericality', 'default')
    assert_equal false, schema.dig('properties', 'active', 'default')
  end
  
  test 'Controller#json_schema.json required' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema['required'].include?('name')
    assert_equal true, schema['required'].exclude?('description')
  end
  
  test 'Controller#json_schema.json readOnly' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema.dig('properties', 'created_at', 'readOnly')
    assert_nil schema.dig('properties', 'name', 'readOnly')
  end
  
  test 'Controller#json_schema.json type' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 'string', schema.dig('properties', 'created_at', 'type')
    assert_equal 'date-time', schema.dig('properties', 'created_at', 'format')
  end
  
  test 'Controller#json_schema.json array' do
    skip "array columns are a Postgres-only feature" if !postgres?

    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 'array', schema.dig('properties', 'aliases', 'type')
    assert_equal 'string', schema.dig('properties', 'aliases', 'items', 'type')

    # The default describes the array, not its elements
    assert_equal [], schema.dig('properties', 'aliases', 'default')
    assert_equal({ 'type' => 'string' }, schema.dig('properties', 'aliases', 'items'))
  end
  
  test 'Controller#json_schema.json validation:numericality' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 1, schema.dig('properties', 'numericality', 'exclusiveMinimum')
    assert_equal 2, schema.dig('properties', 'numericality', 'minimum')
    assert_equal 2, schema.dig('properties', 'numericality', 'maximum')
    assert_equal 3, schema.dig('properties', 'numericality', 'exclusiveMaximum')
  end
  
  test 'Controller#json_schema.json validation:inclusion' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal ['concrete', 'metal', 'brick'], schema.dig('properties', 'build_type', 'enum')
  end
  
  test 'Controller#json_schema.json validation:acceptance' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema.dig('properties', 'agree_to_terms', 'const')
  end
  
  test 'Controller#json_schema.json validation:format' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal "\\d{3}-\\d{3}-\\d{4}", schema.dig('properties', 'phone_number', 'pattern')
  end
  
  test 'Controller#json_schema.json validation:length' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 9, schema.dig('properties', 'phone_number', 'minLength')
    assert_equal 12, schema.dig('properties', 'phone_number', 'maxLength')
  end
  
  test 'Controller#json_schema.json validation:presence' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema['required'].include?('name')
  end


  test 'Controller#json_schema.json for an enum with default' do
    get json_schema_documents_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema.has_key?('properties')
    assert_equal 'string', schema['properties']['level']['type']
    assert_equal 'public', schema['properties']['level']['default']
  end
  
  test 'Controller#json_schema.json for an enum without default' do
    get json_schema_documents_path(format: 'json')

    schema = JSON(response.body)

    assert_equal true, schema.has_key?('properties')
    assert_equal 'string', schema['properties']['rating']['type']
    assert_nil schema['properties']['rating']['default']
  end
  
  test 'Controller#json_schema.json include only' do
    get json_schema_properties_path(format: 'json'), params: { include: {only: ['created_at']} }
    
    schema = JSON(response.body)
    assert_equal ['created_at'], schema['properties'].keys
  end
  
  test 'Controller#json_schema.json include except' do
    get json_schema_properties_path(format: 'json'), params: { include: {except: ['created_at']} }
    
    schema = JSON(response.body)
    assert schema['properties'].keys.exclude?('created_at')
  end
  
  test 'Controller#json_schema.json include has_many' do
    get json_schema_properties_path(format: 'json'), params: { include: 'accounts' }
    
    schema = JSON(response.body)
    assert_equal 'array', schema.dig('properties', 'accounts', 'type')
    assert_equal 'string', schema.dig('properties', 'accounts', 'items', 'properties', 'email', 'type')
  end

  test 'Controller#json_schema.json include belongs_to' do
    get json_schema_photos_path(format: 'json'), params: { include: 'account' }

    schema = JSON(response.body)
    assert_equal 'object', schema.dig('properties', 'account', 'type')
    assert_equal 'string', schema.dig('properties', 'account', 'properties', 'email', 'type')
  end

end
