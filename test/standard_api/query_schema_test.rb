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

  test 'Controller#query_schema.json where reads an object as operators' do
    path = query_schema_cameras_path(format: 'json')

    # CameraACL wheres permit any operator on make, and eq and in on photo_id
    with_camera_schema(proc { attribute :make, :json; attribute :photo_id, :unknown }) do
      schema = query_schema(path)
      schemer = schemer(schema)
      assert JSONSchemer.valid_schema?(schema)

      [
        { 'make' => { 'eq' => { 'a' => 1 } } },
        { 'make' => { 'has_key' => 'a' } },
        { 'make' => true },
        { 'photo_id' => 1 },
        { 'photo_id' => 'a' },
        { 'photo_id' => { 'eq' => 1 } },
        { 'photo_id' => [1, 2] }
      ].each do |where|
        assert schemer.valid?({ 'where' => where, 'limit' => 1 }), where.inspect
      end

      [
        # An object isn't a value to compare with, but operators
        { 'make' => { 'a' => 1 } },
        { 'make' => { 'bogus' => 1 } },
        { 'photo_id' => { 'gt' => 1 } },
        { 'photo_id' => { 'bogus' => 1 } }
      ].each do |where|
        assert_not schemer.valid?({ 'where' => where, 'limit' => 1 }), where.inspect
      end
    end
  end

  test 'Controller#query_schema.json order' do
    schema = query_schema(query_schema_account_path(format: 'json'))
    schemer = schemer(schema)

    names = schema.dig('properties', 'order', 'anyOf', 0, 'enum')
    assert_includes names, 'id'
    assert_includes names, 'property.id'

    # The object is built once, into $defs
    object = { '$ref' => '#/$defs/OrderObject' }
    assert_equal object, schema.dig('properties', 'order', 'anyOf', 1)
    assert_equal object, schema.dig('properties', 'order', 'anyOf', 2, 'items', 'anyOf', 1)
    assert_equal 'object', schema.dig('$defs', 'OrderObject', 'type')

    assert schemer.valid?({ 'order' => 'id', 'limit' => 1 })
    assert schemer.valid?({ 'order' => { 'id' => 'desc' }, 'limit' => 1 })
    assert schemer.valid?({ 'order' => { 'id' => { 'desc' => 'nulls_last' } }, 'limit' => 1 })
    assert schemer.valid?({ 'order' => [{ 'property' => { 'name' => 'asc' } }, 'id'], 'limit' => 1 })
    assert_not schemer.valid?({ 'order' => 'name', 'limit' => 1 })
    assert_not schemer.valid?({ 'order' => { 'id' => 'sideways' }, 'limit' => 1 })
  end

  test 'Controller#query_schema.json order under an empty Hash permit accepts nothing' do
    camera_schema
    defs = StandardAPI::JSONSchema::Query::Defs.new
    controller.send(:order_schema, [:id, { photos: [] }], Camera, defs, 'Order')

    assert_equal({ 'not' => {} }, defs.dig('OrderObject', 'properties', 'photos'))
  end

  test 'Controller#query_schema.json include' do
    schemer = schemer(camera_schema)

    # The object is built once, into $defs
    object = { '$ref' => '#/$defs/Include' }
    assert_equal object, camera_schema.dig('properties', 'include', 'anyOf', 0)
    assert_equal object, camera_schema.dig('properties', 'include', 'anyOf', 2, 'items', 'anyOf', 1)
    assert_equal 'object', camera_schema.dig('$defs', 'Include', 'type')

    assert schemer.valid?({ 'include' => 'photo', 'limit' => 1 })
    assert schemer.valid?({ 'include' => { 'photo' => { 'account' => true } }, 'limit' => 1 })
    assert schemer.valid?({ 'include' => { 'photo' => { 'where' => { 'id' => 1 }, 'limit' => 2 } }, 'limit' => 1 })
    assert schemer.valid?({ 'include' => ['photo', 'specs'], 'limit' => 1 })
    assert_not schemer.valid?({ 'include' => 'camera', 'limit' => 1 })
    assert_not schemer.valid?({ 'include' => { 'photo' => { 'properties' => true } }, 'limit' => 1 })
    # Not ACL checked, but used
    assert schemer.valid?({ 'include' => { 'photo' => { 'distinct_on' => 'id' } }, 'limit' => 1 })
    assert_not schemer.valid?({ 'include' => { 'photo' => { 'offset' => 1 } }, 'limit' => 1 })
  end

  test 'Controller#query_schema.json an include whose name is taken by another is added to it' do
    camera_schema
    defs = StandardAPI::JSONSchema::Query::Defs.new
    ref = { '$ref' => '#/$defs/CameraPhotoInclude' }

    photo = controller.send(:include_schema, { 'account' => {} }, Photo, defs, name: 'CameraPhotoInclude')
    assert_equal ref, photo.dig('anyOf', 0)
    properties = defs.dig('CameraPhotoInclude', 'properties').dup

    # The same include again changes nothing
    controller.send(:include_schema, { 'account' => {} }, Photo, defs, name: 'CameraPhotoInclude')
    assert_equal properties, defs.dig('CameraPhotoInclude', 'properties')

    # Another include adds what it permits, and what both have is unchanged
    other = controller.send(:include_schema, { 'photo' => {} }, Camera, defs, name: 'CameraPhotoInclude')
    assert_equal ref, other.dig('anyOf', 0)
    assert_equal properties.keys + ['photo'], defs.dig('CameraPhotoInclude', 'properties').keys
    assert_equal properties, defs.dig('CameraPhotoInclude', 'properties').except('photo')
  end

  test 'Controller#query_schema.json include order is checked against the included model ACL orders' do
    schema = camera_schema
    schemer = schemer(schema)

    # PhotoACL orders permit id, created_at and account_id
    assert_equal ['id', 'created_at', 'account_id'], schema.dig('$defs', 'PhotoOrder', 'anyOf', 0, 'enum')
    assert_equal({ '$ref' => '#/$defs/PhotoOrderObject' }, schema.dig('$defs', 'PhotoOrder', 'anyOf', 1))
    assert schemer.valid?({ 'include' => { 'photo' => { 'order' => { 'id' => 'desc' } } }, 'limit' => 1 })
    assert_not schemer.valid?({ 'include' => { 'photo' => { 'order' => { 'format' => 'asc' } } }, 'limit' => 1 })

    get cameras_path(format: 'json'), params: { include: { photo: { order: { format: 'asc' } } }, limit: 1 }
    assert_response :bad_request
  end

  test 'Controller#query_schema.json group_by lists the model columns' do
    schema = camera_schema
    schemer = schemer(schema)

    assert_equal Camera.column_names, schema.dig('properties', 'group_by', 'anyOf', 0, 'enum')
    assert schemer.valid?({ 'select' => { 'count' => '*' }, 'group_by' => ['make', 'hidden'] })
    assert_not schemer.valid?({ 'select' => { 'count' => '*' }, 'group_by' => 'cameras.make' })

    get calculate_cameras_path(format: 'json'), params: { select: { count: '*' }, group_by: 'cameras.make' }
    assert_response :bad_request
  end

  test 'Controller#query_schema.json params the ACL does not check' do
    properties = camera_schema['properties']

    %w(distinct_on join select).each do |name|
      assert_match 'Not checked by the ACL.', properties.dig(name, 'description'), name
    end
    assert_no_match 'Not checked by the ACL.', properties.dig('group_by', 'description')
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
    create(:camera, photo: create(:photo))
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
  end

  test 'Controller#query_schema_for is public and gives what query_schema.json renders' do
    assert_equal camera_schema, controller.query_schema_for(Camera).as_json
  end

  test 'Controller#query_schema_for with ref leaves other models to the caller' do
    camera_schema
    refs = []
    schema = controller.query_schema_for(Camera, ref: ->(model, kind) {
      refs << [model, kind]
      { '$ref' => "test://#{model.model_name.plural}##{kind}" } if model == Photo
    }).as_json

    # Only Camera's own where, when and top-level include are built
    assert_equal ['CameraWhere', 'CameraWhen', 'Include'].sort, schema['$defs'].keys.sort
    assert_equal({ '$ref' => 'test://photos#Where' }, resolve(schema, schema.dig('properties', 'where')).dig('anyOf', 0, 'properties', 'photo', 'anyOf', 1))
    assert_includes refs, [Photo, 'Include']
    assert_not_includes refs.map(&:first), Camera

    # Returning nil builds it, as without ref
    assert_equal camera_schema, controller.query_schema_for(Camera, ref: ->(*) { nil }).as_json
  end

  test 'Controller#query_schema_for can be called from the ref of another' do
    camera_schema
    ref = ->(model, kind) { { '$ref' => "test://#{model.model_name.plural}##{kind}" } }
    expected = controller.query_schema_for(Camera, ref: ref).as_json

    built = []
    schema = controller.query_schema_for(Camera, ref: ->(model, kind) {
      built << controller.query_schema_for(model).as_json
      ref.call(model, kind)
    }).as_json

    assert_not_empty built
    assert_equal expected, schema
  end

end
