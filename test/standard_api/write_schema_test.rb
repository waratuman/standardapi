require 'standard_api/test_helper'

class WriteSchemaTest < ActionDispatch::IntegrationTest

  def write_schema(path, **params)
    get path, params: params
    assert_response :ok
    JSON(response.body)
  end

  def property_schema
    write_schema(write_schema_properties_path(format: 'json')).dig('properties', 'property')
  end

  def camera_schema
    write_schema(write_schema_cameras_path(format: 'json')).dig('properties', 'camera')
  end

  # The JSON Schema of +attribute+ in cameras' write_schema.json, with the
  # +validations+ given to it through the ACL's schemas
  def camera_attribute_schema(attribute, validations)
    ApplicationController.define_method(:camera_schemas) do |default_schema|
      default_schema.map { |s| s[:name] == attribute ? s.merge(validations: validations) : s }
    end
    ApplicationController.send(:private, :camera_schemas)

    camera_schema.dig('properties', attribute)
  ensure
    ApplicationController.send(:remove_method, :camera_schemas)
  end

  test 'Controller#write_schema_for is public and gives what write_schema.json renders' do
    schema = camera_schema

    assert_equal schema, controller.write_schema_for(Camera).as_json.dig('properties', 'camera')
  end

  test 'Controller#write_schema.json is a JSON Schema of the model param' do
    schema = write_schema(write_schema_cameras_path(format: 'json'))

    assert_equal 'https://json-schema.org/draft/2020-12/schema', schema['$schema']
    assert_equal 'object', schema['type']
    assert_equal ['camera'], schema['properties'].keys
    assert_equal false, schema.dig('properties', 'camera', 'additionalProperties')
  end

  test 'Controller#write_schema.json only lists attributes the ACL permits' do
    schema = write_schema(write_schema_cameras_path(format: 'json'))

    assert_equal ['make', 'hidden', 'retired', 'photo_id'], schema.dig('properties', 'camera', 'properties').keys
  end

  test 'Controller#write_schema.json without ACL attributes lists none' do
    schema = write_schema(write_schema_references_path(format: 'json'))

    assert_equal({}, schema.dig('properties', 'reference', 'properties'))
  end

  test 'Controller#write_schema.json table description' do
    skip "Adapter does not support comments on databases" if !mariadb? && !postgres?

    schema = write_schema(write_schema_documents_path(format: 'json'))
    assert_equal 'I <3 Documents', schema['description']
  end

  test 'Controller#write_schema.json types' do
    properties = property_schema['properties']

    assert_equal ['string', 'null'], properties.dig('name', 'type')
    # A decimal may be sent as a number or a String
    assert_equal ['number', 'string', 'null'], properties.dig('size', 'type')
    assert_equal 'string', write_schema(write_schema_cameras_path(format: 'json')).dig('properties', 'camera', 'properties', 'make', 'type')
  end

  test 'Controller#write_schema.json defaults' do
    properties = property_schema['properties']

    assert_equal 2, properties.dig('numericality', 'default')
    assert_equal false, properties.dig('active', 'default')
    assert_nil properties['description']['default']
  end

  test 'Controller#write_schema.json array' do
    skip "array columns are a Postgres-only feature" if !postgres?

    aliases = property_schema.dig('properties', 'aliases')
    assert_equal ['array', 'null'], aliases['type']
    # The default describes the array, not its elements
    assert_equal [], aliases['default']
    assert_equal({ 'type' => 'string' }, aliases['items'])
  end

  test 'Controller#write_schema.json description from the ACL schemas' do
    assert_equal 'The manufacturer', camera_schema.dig('properties', 'make', 'description')
  end

  test 'Controller#write_schema.json lists a definition the ACL schemas adds when the ACL permits it' do
    ApplicationController.define_method(:camera_schemas) do |default_schema|
      default_schema + [{ name: 'thumbnail_url', type: 'string' }]
    end
    ApplicationController.send(:private, :camera_schemas)
    CamerasController.any_instance.stubs(:camera_attributes).returns([:make, :thumbnail_url])

    # null defaults to true
    assert_equal({ 'type' => ['string', 'null'] }, camera_schema.dig('properties', 'thumbnail_url'))
  ensure
    ApplicationController.send(:remove_method, :camera_schemas)
  end

  test 'Controller#write_schema.json an attr_readonly attribute the ACL permits is readOnly and required' do
    Camera.stubs(:readonly_attribute?).returns(false)
    Camera.stubs(:readonly_attribute?).with('make').returns(true)

    schema = camera_schema
    assert_equal true, schema.dig('properties', 'make', 'readOnly')
    assert_includes schema['required'], 'make'
  end

  test 'Controller#write_schema.json an auto populated attribute the ACL permits is not readOnly or required' do
    CamerasController.any_instance.stubs(:camera_attributes).returns([:id, :make])

    schema = camera_schema
    # id is filled in by the database, but can be given
    assert_nil schema.dig('properties', 'id', 'readOnly')
    assert_not_includes schema['required'], 'id'
  end

  test 'Controller#write_schema.json inclusion validations' do
    inclusion = ->(values) { [{ kind: :inclusion, options: { in: values } }] }

    assert_equal %w[a b], camera_attribute_schema('make', inclusion.(%w[a b]))['enum']
    # photo_id allows NULL
    assert_equal({ 'type' => ['integer', 'null'], 'minimum' => 1, 'maximum' => 10 }, camera_attribute_schema('photo_id', inclusion.(1..10)))
    assert_equal({ 'type' => ['integer', 'null'], 'minimum' => 1, 'exclusiveMaximum' => 10 }, camera_attribute_schema('photo_id', inclusion.(1...10)))
    assert_equal({ 'type' => ['integer', 'null'], 'minimum' => 5 }, camera_attribute_schema('photo_id', inclusion.(5..)))
    # JSON Schema can't describe a Range of Strings or a Proc
    assert_equal({ 'type' => 'string' }, camera_attribute_schema('make', inclusion.('a'..'z')))
    assert_equal({ 'type' => 'string' }, camera_attribute_schema('make', inclusion.(->(_) { %w[a] })))
  end

  test 'Controller#write_schema.json format validations' do
    format = ->(with) { [{ kind: :format, options: { with: with } }] }

    assert_equal '\\d{3}-\\d{4}', camera_attribute_schema('make', format.(/\d{3}-\d{4}/))['pattern']
    assert_equal '(?:a|b)c', camera_attribute_schema('make', format.(/(?:a|b)c/))['pattern']
    # JavaScript doesn't read these the way Ruby does
    [/\A\d+\z/, /(?i)abc/, /abc/i, /\h+/, ->(_) { /x/ }].each do |with|
      assert_nil camera_attribute_schema('make', format.(with))['pattern'], with.inspect
    end
  end

  test 'Controller#write_schema.json required on create' do
    assert_equal ['name'], property_schema['required']
    # schemas_for requires a NOT NULL column even with a default, as hidden
    # and retired have
    assert_equal ['make', 'hidden', 'retired'], camera_schema['required']
  end

  test 'Controller#write_schema.json nested attributes' do
    properties = property_schema['properties']

    assert_equal ['array', 'null'], properties.dig('accounts', 'type')
    assert_equal ['id', 'property_id', 'name'], properties.dig('accounts', 'items', 'properties').keys
    assert_equal 'integer', properties.dig('account_ids', 'items', 'type')

    photo = properties.dig('photos', 'items', 'properties')
    assert_equal ['id', 'format', 'account_id', 'account', 'camera'], photo.keys
    assert_equal ['integer', 'null'], photo.dig('account_id', 'type')
    assert_equal ['object', 'null'], photo.dig('account', 'type')
    assert_nil properties.dig('photos', 'items', 'required')
  end

  test 'Controller#write_schema.json enum' do
    DocumentsController.any_instance.stubs(:document_attributes).returns([:level, :rating])
    properties = write_schema(write_schema_documents_path(format: 'json')).dig('properties', 'document', 'properties')

    assert_equal 'string', properties.dig('level', 'type')
    assert_equal ['public', 'secret'], properties.dig('level', 'enum')
    assert_equal 'public', properties.dig('level', 'default')
    assert_equal ['string', 'null'], properties.dig('rating', 'type')
    assert_equal ['poor', 'ok', 'good', nil], properties.dig('rating', 'enum')
  end

  test 'Controller#write_schema.json validations' do
    PropertiesController.any_instance.stubs(:property_attributes).returns([
      :numericality, :build_type, :agree_to_terms, :phone_number
    ])
    properties = property_schema['properties']

    assert_equal 1, properties.dig('numericality', 'exclusiveMinimum')
    assert_equal 2, properties.dig('numericality', 'minimum')
    assert_equal 2, properties.dig('numericality', 'maximum')
    assert_equal 3, properties.dig('numericality', 'exclusiveMaximum')
    assert_equal ['concrete', 'metal', 'brick', nil], properties.dig('build_type', 'enum')
    assert_equal true, properties.dig('agree_to_terms', 'const')
    assert_equal '\d{3}-\d{3}-\d{4}', properties.dig('phone_number', 'pattern')
    assert_equal 9, properties.dig('phone_number', 'minLength')
    assert_equal 12, properties.dig('phone_number', 'maxLength')
  end

  test 'Controller#write_schema.json is a valid JSON Schema' do
    %w(properties photos documents references cameras).each do |resources|
      schema = write_schema(send("write_schema_#{resources}_path", format: 'json'))

      assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).map { |e| "#{resources} #{e['error']}" }.join("\n")
    end
  end

  test 'Controller#create.json params validate against Controller#write_schema.json' do
    schemer = JSONSchemer.schema(write_schema(write_schema_properties_path(format: 'json')))
    params = { 'property' => {
      'name' => 'Tower', 'size' => 10.5, 'active' => true,
      'accounts' => [{ 'name' => 'Tenant' }]
    } }

    assert_empty schemer.validate(params).map { |e| e['error'] }
    assert_not schemer.valid?({ 'property' => { 'name' => 'Tower', 'created_at' => '2026-01-01' } })
    assert_not schemer.valid?({ 'property' => { 'description' => 'no name' } })

    post properties_path(format: 'json'), params: params, as: :json
    assert_response :created
  end

end
