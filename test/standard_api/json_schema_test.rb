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

  test 'Controller#json_schema.json renders a definition the ACL schemas adds with only a name and type' do
    ApplicationController.define_method(:camera_schemas) do |default_schema|
      default_schema + [{ name: 'thumbnail_url', type: 'string' }]
    end
    ApplicationController.send(:private, :camera_schemas)

    get json_schema_cameras_path(format: 'json')
    assert_response :ok
    # null defaults to true, and CameraACL#attributes doesn't permit it, so
    # it's read only
    assert_equal({ 'type' => ['string', 'null'], 'readOnly' => true }, JSON(response.body).dig('properties', 'thumbnail_url'))
  ensure
    ApplicationController.send(:remove_method, :camera_schemas)
  end

  test 'Controller#json_schema.json an attr_readonly attribute the ACL permits is readOnly and required' do
    Camera.stubs(:readonly_attribute?).returns(false)
    Camera.stubs(:readonly_attribute?).with('make').returns(true)

    get json_schema_cameras_path(format: 'json')
    schema = JSON(response.body)
    assert_equal true, schema.dig('properties', 'make', 'readOnly')
    assert_includes schema['required'], 'make'
  end

  test 'Controller#json_schema.json an auto populated attribute the ACL permits is not readOnly or required' do
    ApplicationController.define_method(:camera_attributes) { |record = nil| [:id, :make] }
    ApplicationController.send(:private, :camera_attributes)

    get json_schema_cameras_path(format: 'json')
    schema = JSON(response.body)
    # id is filled in by the database, but can be given
    assert_nil schema.dig('properties', 'id', 'readOnly')
    assert_not_includes schema['required'], 'id'
  ensure
    ApplicationController.send(:remove_method, :camera_attributes)
  end

  test 'records validate against their json_schema.json' do
    property = create(:property, photos: [create(:photo)])
    pages = {
      property_path(property, format: 'json', include: { photos: true, landlord: true }) => json_schema_properties_path(format: 'json', include: { photos: true, landlord: true }),
      photo_path(property.photos.first, format: 'json') => json_schema_photos_path(format: 'json'),
      document_path(create(:document), format: 'json') => json_schema_documents_path(format: 'json'),
      reference_path(create(:reference), format: 'json') => json_schema_references_path(format: 'json'),
      camera_path(create(:camera), format: 'json') => json_schema_cameras_path(format: 'json')
    }
    # contentMediaType is only an annotation; json_schemer needs to be told so
    media_types = { 'application/octet-stream' => ->(_) { [true, nil] } }

    pages.each do |record_path, schema_path|
      get schema_path
      schema = JSONSchemer.schema(JSON(response.body), content_media_types: media_types)
      get record_path
      record = JSON(response.body)

      errors = schema.validate(record).map { |e| "#{e['data_pointer']}: #{e['type']}" }
      assert_empty errors, "#{record_path} doesn't validate against #{schema_path}"
    end
  end

  test 'Controller#json_schema.json an included association is nullable unless its presence is validated' do
    # Photo's belongs_to :account is optional in the test app
    get json_schema_photos_path(format: 'json'), params: { include: 'account' }
    assert_equal ['object', 'null'], JSON(response.body).dig('properties', 'account', 'type')

    # A required belongs_to (optional: false, or belongs_to_required_by_default)
    # validates its presence
    Photo.stubs(:validators_on).returns([])
    Photo.stubs(:validators_on).with(:account).returns([ActiveRecord::Validations::PresenceValidator.new(attributes: [:account])])
    get json_schema_photos_path(format: 'json'), params: { include: 'account' }
    assert_equal 'object', JSON(response.body).dig('properties', 'account', 'type')

    # A has_one may have no record
    get json_schema_properties_path(format: 'json'), params: { include: 'landlord' }
    assert_equal ['object', 'null'], JSON(response.body).dig('properties', 'landlord', 'type')
  end

  test 'Controller#json_schema.json inclusion validations' do
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
    assert_equal ['array', 'null'], schema.dig('properties', 'aliases', 'type')
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
    # build_type allows NULL
    assert_equal ['concrete', 'metal', 'brick', nil], schema.dig('properties', 'build_type', 'enum')
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
    # rating allows NULL
    assert_equal ['string', 'null'], schema['properties']['rating']['type']
    assert_equal ['poor', 'ok', 'good', nil], schema['properties']['rating']['enum']
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
    assert_equal ['string', 'null'], schema.dig('properties', 'accounts', 'items', 'properties', 'email', 'type')
  end

  test 'Controller#json_schema.json include belongs_to' do
    get json_schema_photos_path(format: 'json'), params: { include: 'account' }

    schema = JSON(response.body)
    # A photo may have no account
    assert_equal ['object', 'null'], schema.dig('properties', 'account', 'type')
    assert_equal ['string', 'null'], schema.dig('properties', 'account', 'properties', 'email', 'type')
  end

end
