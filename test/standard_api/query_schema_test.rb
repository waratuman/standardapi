require 'standard_api/test_helper'

class QuerySchemaTest < ActionDispatch::IntegrationTest

  def query_schema(path)
    get path
    assert_response :ok
    JSON(response.body)
  end

  def camera_schema
    @camera_schema ||= query_schema(query_schema_cameras_path(format: 'json'))
  end

  def schemer(schema)
    JSONSchemer.schema(schema)
  end

  def resolve(schema, ref)
    schema.dig(*ref['$ref'].delete_prefix('#/').split('/'))
  end

  test 'Controller#query_schema.json is a valid JSON Schema' do
    [camera_schema, query_schema(query_schema_properties_path(format: 'json'))].each do |schema|
      assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).map { |e| e['error'] }.join("\n")
    end
  end

  test 'Controller#query_schema.json limit and offset' do
    assert_equal({ 'type' => 'integer', 'minimum' => 0, 'maximum' => 1000 }, camera_schema.dig('properties', 'limit'))
    assert_equal [{ 'required' => ['limit'] }, { 'required' => ['select'] }], camera_schema['anyOf']
    assert_equal 'integer', camera_schema.dig('properties', 'offset', 'type')
    assert_not schemer(camera_schema).valid?({ 'where' => { 'id' => 1 } })

    schema = query_schema(query_schema_unlimited_index_path(format: 'json'))
    assert_nil schema.dig('properties', 'limit', 'maximum')
    assert_nil schema['anyOf']
  end

  test 'Controller#query_schema.json where only lists the ACL wheres' do
    where = camera_schema.dig('$defs', 'CameraWhere', 'anyOf', 0, 'properties')

    assert_equal ['id', 'make', 'photo_id', 'photo'], where.keys
    # Only the operators the ACL lists
    assert_equal ['eq', 'in'], where.dig('photo_id', 'anyOf').last['properties'].keys
    # Any operator, narrowed to the ones for a string
    assert_includes where.dig('make', 'anyOf').last['properties'].keys, 'ilike'
    assert_not_includes where.dig('id', 'anyOf').last['properties'].keys, 'ilike'
    # An association refers to the associated model's wheres
    assert_equal({ '$ref' => '#/$defs/PhotoWhere' }, where.dig('photo', 'anyOf', 1))
    assert_equal ['id', 'account_id', 'properties'], camera_schema.dig('$defs', 'PhotoWhere', 'anyOf', 0, 'properties').keys
  end

  test 'Controller#query_schema.json without ACL wheres has no where' do
    assert_nil query_schema(query_schema_references_path(format: 'json')).dig('properties', 'where')
  end

  test 'Controller#query_schema.json accepts the wheres the server accepts' do
    schemer = schemer(camera_schema)
    [
      { 'where' => { 'make' => 'Sony' } },
      { 'where' => { 'make' => { 'ilike' => 'so%' } } },
      { 'where' => { 'photo_id' => [1, 2] } },
      { 'where' => [{ 'make' => 'Sony' }, 'OR', { 'id' => 1 }] },
      { 'where' => { 'photo' => { 'account_id' => 1 } } },
      { 'where' => { 'photo' => true } }
    ].each do |query|
      assert schemer.valid?(query.merge('limit' => 1)), query.inspect

      get cameras_path(format: 'json'), params: query.merge(limit: 1)
      assert_response :ok, query.inspect
    end
  end

  test 'Controller#query_schema.json rejects the wheres the server rejects' do
    schemer = schemer(camera_schema)
    [
      { 'where' => { 'hidden' => true } },
      { 'where' => { 'photo_id' => { 'gt' => 1 } } },
      { 'where' => { 'photo' => { 'format' => 'jpg' } } },
      { 'where' => [{ 'make' => 'Sony' }, 'OR', { 'hidden' => true }] }
    ].each do |query|
      assert_not schemer.valid?(query.merge('limit' => 1)), query.inspect

      get cameras_path(format: 'json'), params: query.merge(limit: 1)
      assert_response :bad_request, query.inspect
    end
  end

  test 'Controller#query_schema.json order' do
    schema = query_schema(query_schema_account_path(format: 'json'))
    schemer = schemer(schema)

    names = schema.dig('properties', 'order', 'anyOf', 0, 'enum')
    assert_includes names, 'id'
    assert_includes names, 'property.id'

    assert schemer.valid?({ 'order' => 'id', 'limit' => 1 })
    assert schemer.valid?({ 'order' => { 'id' => 'desc' }, 'limit' => 1 })
    assert schemer.valid?({ 'order' => { 'id' => { 'desc' => 'nulls_last' } }, 'limit' => 1 })
    assert schemer.valid?({ 'order' => [{ 'property' => { 'name' => 'asc' } }, 'id'], 'limit' => 1 })
    assert_not schemer.valid?({ 'order' => 'name', 'limit' => 1 })
    assert_not schemer.valid?({ 'order' => { 'id' => 'sideways' }, 'limit' => 1 })
  end

  test 'Controller#query_schema.json include' do
    schemer = schemer(camera_schema)

    assert schemer.valid?({ 'include' => 'photo', 'limit' => 1 })
    assert schemer.valid?({ 'include' => { 'photo' => { 'account' => true } }, 'limit' => 1 })
    assert schemer.valid?({ 'include' => { 'photo' => { 'where' => { 'id' => 1 }, 'limit' => 2 } }, 'limit' => 1 })
    assert schemer.valid?({ 'include' => ['photo', 'specs'], 'limit' => 1 })
    assert_not schemer.valid?({ 'include' => 'camera', 'limit' => 1 })
    assert_not schemer.valid?({ 'include' => { 'photo' => { 'properties' => true } }, 'limit' => 1 })
    assert schemer.valid?({ 'include' => { 'photo' => { 'when' => { 'make' => 'Canon' } } }, 'limit' => 1 })
    # Not ACL checked, but used
    assert schemer.valid?({ 'include' => { 'photo' => { 'order' => { 'id' => 'desc' }, 'distinct_on' => 'id' } }, 'limit' => 1 })
    assert_not schemer.valid?({ 'include' => { 'photo' => { 'offset' => 1 } }, 'limit' => 1 })
  end

  test 'Controller#query_schema.json params the ACL does not check' do
    properties = camera_schema['properties']

    %w(distinct_on join group_by select).each do |name|
      assert_match 'Not checked by the ACL.', properties.dig(name, 'description'), name
    end
    assert_equal ['photo'], properties.dig('join', 'enum')
  end

  test 'Controller#query_schema.json include when lists the attributes the ACL wheres permit an eq on' do
    schema = camera_schema

    # CameraACL wheres permit any operator on id and make, and eq on photo_id
    assert_equal ['id', 'make', 'photo_id'], schema.dig('$defs', 'CameraWhen', 'properties').keys
    assert_equal false, schema.dig('$defs', 'CameraWhen', 'additionalProperties')

    schemer = schemer(schema)
    assert schemer.valid?({ 'include' => { 'photo' => { 'when' => { 'make' => 'Canon' } } }, 'limit' => 1 })
    assert_not schemer.valid?({ 'include' => { 'photo' => { 'when' => { 'hidden' => false } } }, 'limit' => 1 })

    get cameras_path(format: 'json'), params: { include: { photo: { when: { hidden: false } } }, limit: 1 }
    assert_response :bad_request
  end

  test 'Controller#query_schema.json accepts the unchecked params the server accepts' do
    camera = create(:camera, photo: create(:photo))
    schemer = schemer(camera_schema)
    queries = [
      [cameras_path(format: 'json'), { 'join' => 'photo', 'limit' => 1 }],
      [cameras_path(format: 'json'), { 'include' => { 'photo' => { 'when' => { 'make' => 'Canon' } } }, 'limit' => 1 }],
      [calculate_cameras_path(format: 'json'), { 'select' => { 'count' => '*' } }],
      [calculate_cameras_path(format: 'json'), { 'select' => [{ 'maximum' => 'id' }, { 'count' => { 'distinct' => 'make' } }] }],
      [calculate_cameras_path(format: 'json'), { 'select' => { 'count' => '*' }, 'group_by' => 'make' }]
    ]
    queries << [cameras_path(format: 'json'), { 'distinct_on' => 'make', 'limit' => 1 }] if postgres?

    queries.each do |path, query|
      assert schemer.valid?(query), query.inspect

      get path, params: query
      assert_response :ok, query.inspect
    end

    assert_not schemer.valid?({ 'join' => 'camera', 'limit' => 1 })
    assert_not schemer.valid?({ 'select' => { 'median' => 'id' } })
    assert camera
  end

end
