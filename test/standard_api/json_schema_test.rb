require 'standard_api/test_helper'

class JSONSchemaTest < ActionDispatch::IntegrationTest
  
  test 'Controller#json_schema.json' do
    get json_schema_cameras_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema.has_key?('properties')
    assert_equal true, schema['required'].include?('make')
  end
  
  test 'Controller#json_schema.json table description' do
    get json_schema_documents_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 'I <3 Documents', schema['description']
  end
  
  test 'Controller#json_schema.json default' do
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 2, schema.dig('properties', 'numericality', 'default')
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
    get json_schema_properties_path(format: 'json')

    schema = JSON(response.body)
    assert_equal 'array', schema.dig('properties', 'aliases', 'type')
    assert_equal 'string', schema.dig('properties', 'aliases', 'items', 'type')
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
    assert_equal "(?-mix:\\d{3}-\\d{3}-\\d{4})", schema.dig('properties', 'phone_number', 'pattern')
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
