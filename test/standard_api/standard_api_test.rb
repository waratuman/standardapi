require 'standard_api/test_helper'

class PropertiesControllerTest < ActionDispatch::IntegrationTest
  include StandardAPI::TestCase
  include StandardAPI::Helpers

  self.includes = [ :photos, :landlord, :english_name ]

  def normalizers
    {
      Property => {
        "size" => lambda { |value| value.round(4).to_s }
      }
    }
  end

  # = Routing Tests
  #
  # These also can't be included in StandardAPI::TestCase because we don't know
  # how the other's routes are setup

  # test 'route to #metadata' do
  #   assert_routing '/metadata', path_with_action('metadata')
  #   assert_recognizes path_with_action('metadata'), "/metadata"
  # end

  test 'route to #tables.json' do
    assert_recognizes({"controller"=>"application", "action"=>"tables"}, { method: :get, path: "/tables" })
  end

  test 'route to #create.json' do
    assert_routing({ method: :post, path: "/#{plural_name}" }, path_with_action('create'))
    assert_recognizes(path_with_action('create'), { method: :post, path: "/#{plural_name}" })
  end

  test 'route to #calculate.json' do
    assert_routing "/#{plural_name}/calculate", path_with_action('calculate')
    assert_recognizes(path_with_action('calculate'), "/#{plural_name}/calculate")
  end

  test 'route to #destroy.json' do
    assert_routing({ method: :delete, path: "/#{plural_name}/1" }, path_with_action('destroy', id: '1'))
    assert_recognizes(path_with_action('destroy', id: '1'), { method: :delete, path: "/#{plural_name}/1" })
  end

  test 'route to #index.json' do
    assert_routing "/#{plural_name}", path_with_action('index')
    assert_recognizes path_with_action('index'), "/#{plural_name}"
  end

  test 'route to #show.json' do
    assert_routing "/#{plural_name}/1", path_with_action('show', id: '1')
    assert_recognizes(path_with_action('show', id: '1'), "/#{plural_name}/1")
  end

  test 'route to #update.json' do
    assert_routing({ method: :put, path: "#{plural_name}/1" }, path_with_action('update', id: '1'))
    assert_recognizes(path_with_action('update', id: '1'), { method: :put, path: "/#{plural_name}/1" })
    assert_routing({ method: :patch, path: "/#{plural_name}/1" }, path_with_action('update', id: '1'))
    assert_recognizes(path_with_action('update', id: '1'), { method: :patch, path: "/#{plural_name}/1" })
  end

  test 'route to #schema.json' do
    assert_routing({ method: :get, path: "/#{plural_name}/schema" }, path_with_action('schema'))
    assert_recognizes(path_with_action('schema'), { method: :get, path: "/#{plural_name}/schema" })
  end

  # = Controller Tests

  test 'include StandardAPI includes Controller and AccessControlList' do
    klass = Class.new(ActionController::Base) do
      include StandardAPI
    end
    assert klass.ancestors.include?(StandardAPI::Controller), "Expected StandardAPI::Controller to be included"
    assert klass.ancestors.include?(StandardAPI::AccessControlList), "Expected StandardAPI::AccessControlList to be included"
  end

  test 'StandardAPI-Version' do
    get schema_references_path(format: 'json')
    assert_equal StandardAPI::VERSION, response.headers['StandardAPI-Version']
  end

  test 'Controller#new' do
    @controller = ReferencesController.new
    assert_equal @controller.send(:model), Reference

    @controller = SessionsController.new
    assert_nil @controller.send(:model)
    get new_session_path
    assert_response :ok
  end

  test 'Controller#model_orders defaults to []' do
    @controller = ReferencesController.new
    assert_equal @controller.send(:model_orders), []
  end

  test 'Controller#model_includes defaults to []' do
    @controller = DocumentsController.new
    assert_equal @controller.send(:model_includes), []
  end

  test 'Controller#model_params defaults to ActionController::Parameters' do
    @controller = DocumentsController.new
    @controller.params = ActionController::Parameters.new
    @controller.action_name = 'create'
    assert_equal @controller.send(:model_params), ActionController::Parameters.new
  end

  test 'Controller#model_params defaults to ActionController::Parameters when no resource_attributes' do
    @controller = ReferencesController.new
    @controller.params = ActionController::Parameters.new
    @controller.action_name = 'create'
    assert_equal @controller.send(:model_params), ActionController::Parameters.new
  end

  test 'Controller#model_params is conditional based on existing resource' do
    document = create(:document, type: 'movie')
    @controller = DocumentsController.new
    @controller.params = ActionController::Parameters.new(id: document.id, document: {rating: 5})
    assert_equal @controller.send(:model_params).to_h, {"rating" => 5}

    document = create(:document, type: 'book')
    @controller = DocumentsController.new
    @controller.params = ActionController::Parameters.new(id: document.id, document: {rating: 5})
    assert_equal @controller.send(:model_params).to_h, {}
  end

  test 'Controller#mask' do
    @controller = ReferencesController.new
    @controller.define_singleton_method(:mask_for) do |table_name|
      {subject_id: 1}
    end
    @controller.params = {}
    assert_equal 'SELECT "references".* FROM "references" WHERE "references"."subject_id" = 1', @controller.send(:resources).to_sql
  end

  test "Auto includes on a controller without a model" do
    @controller = SessionsController.new
    assert_nil @controller.send(:model)
    post sessions_path(format: :json), params: {session: {user: 'user', pass: 'pass'}}
    assert_response :ok
  end

  test 'ApplicationController#schema.json' do
    get schema_path(format: 'json')

    schema = JSON(response.body)
    controllers = ApplicationController.descendants
    controllers.select! { |c| c.ancestors.include?(StandardAPI::Controller) && c != StandardAPI::Controller }

    @controller.send(:models).reject { |x| %w(Photo Document).include?(x.name)  }.each do |model|
      assert_equal true, schema['models'].has_key?(model.name)

      model_comment = model.connection.table_comment(model.table_name)
      if model_comment.nil? then
        assert_nil schema.dig('models', model.name, 'comment')
      else
        assert_equal model_comment, schema.dig('models', model.name, 'comment')
      end

      model.columns.each do |column|
        assert_equal json_column_type(column.sql_type), schema.dig('models', model.name, 'attributes', column.name, 'type')
        default = column.default
        if !default.nil?
          default = column.fetch_cast_type(model.connection).deserialize(default)
          assert_equal default, schema.dig('models', model.name, 'attributes', column.name, 'default')
        else
          assert_nil schema.dig('models', model.name, 'attributes', column.name, 'default')
        end
        assert_equal column.name == model.primary_key, schema.dig('models', model.name, 'attributes', column.name, 'primary_key')
        assert_equal column.null, schema.dig('models', model.name, 'attributes', column.name, 'null')
        assert_equal column.array, schema.dig('models', model.name, 'attributes', column.name, 'array')
        if column.comment
          assert_equal column.comment, schema.dig('models', model.name, 'attributes', column.name, 'comment')
        else
          assert_nil schema.dig('models', model.name, 'attributes', column.name, 'comment')
        end

        if column.respond_to?(:auto_populated?)
          assert_equal !!column.auto_populated?, schema.dig('models', model.name, 'attributes', column.name, 'auto_populated')
        end
      end
    end

    assert_equal true, schema['models']['Account']['attributes']['id']['readonly']
    assert_equal false, schema['models']['Account']['attributes']['name']['readonly']

    assert_equal [
      {"format"=>{"allow_nil"=>true, "with"=>"(?-mix:.+@.+)"}}
    ], schema['models']['Account']['attributes']['email']['validations']

    assert_equal [
      { "presence" => true }
    ], schema['models']['Property']['attributes']['name']['validations']

    assert_equal [
      { "numericality" => {
          "greater_than" => 1,
          "greater_than_or_equal_to" => 2,
          "equal_to" => 2,
          "less_than_or_equal_to" => 2,
          "less_than" => 3,
          "other_than" => 0,
          "even" => true,
          "in" => "1..3"
        }
      }
    ], schema['models']['Property']['attributes']['numericality']['validations']

    assert_equal 'test comment', schema['comment']
  end

  test 'Controller#schema.json' do
    get schema_references_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema.has_key?('attributes')
    assert_equal true, schema['attributes']['id']['primary_key']
    assert_equal 1000, schema['limit']
  end

  test 'Controller#schema.json w/o limit' do
    get schema_unlimited_index_path(format: 'json')

    schema = JSON(response.body)
    assert_equal true, schema.has_key?('attributes')
    assert_equal true, schema['attributes']['id']['primary_key']
    assert_nil schema['limit']
  end

  test 'Controller#schema.json for an enum with default' do
    get schema_documents_path(format: 'json')

    schema = JSON(response.body)

    assert_equal true, schema.has_key?('attributes')
    assert_equal 'string', schema['attributes']['level']['type']
    assert_equal 'public', schema['attributes']['level']['default']
  end

  test 'Controller#schema.json for an enum without default' do
    get schema_documents_path(format: 'json')

    schema = JSON(response.body)

    assert_equal true, schema.has_key?('attributes')
    assert_equal 'string', schema['attributes']['rating']['type']
    assert_nil schema['attributes']['rating']['default']
  end

  test 'Controller#index w/o limit' do
    account = create(:account)
    get unlimited_index_path(format: 'json')

    assert_equal [account.id], JSON(response.body).map { |x| x['id'] }
  end

  test 'Controller#index with default limit' do
    create(:account)
    get default_limit_index_path(format: 'json')
    assert_response :ok
  end

  test 'Controller#create redirects to correct route with STI models' do
    attrs = attributes_for(:pdf)
    post documents_path, params: { document: attrs }
    assert_response :redirect
  end

  test 'Controller#update redirects to correct route with STI models' do
    pdf = create(:pdf)
    patch document_path(pdf), params: { document: pdf.attributes }
    assert_redirected_to document_path(pdf)
  end

  test 'Controller#create has Affected-Rows header' do
    attrs = attributes_for(:property)
    post properties_path, params: { property: attrs }, as: :json
    assert_equal response.headers['Affected-Rows'], 1

    attrs = attributes_for(:property, :invalid)
    post properties_path, params: { property: attrs }, as: :json
    assert_equal response.headers['Affected-Rows'], 0
  end

  test 'Controller#update has Affected-Rows header' do
    property = create(:property)
    patch property_path(property), params: { property: property.attributes }, as: :json
    assert_equal response.headers['Affected-Rows'], 1

    attrs = attributes_for(:property, :invalid)
    patch property_path(property), params: { property: attrs }, as: :json
    assert_equal response.headers['Affected-Rows'], 0
  end

  test 'Controller#destroy has Affected-Rows header' do
    property = create(:property)
    delete property_path(property), as: :json
    assert_equal response.headers['Affected-Rows'], 1

    assert_raises ActiveRecord::RecordNotFound do
      delete property_path(property), as: :json
      assert_equal response.headers['Affected-Rows'], 0
    end
  end

  # = View Tests

  test 'rendering tables' do
    get tables_path(format: 'json')
    assert_response :ok
    # assert_equal ['properties', 'accounts', 'photos', 'references', 'sessions', 'unlimited'], response.parsed_body
    # Multiple 'accounts' because multiple controllers with that model for testing.
    assert_equal ["properties", "accounts", "cameras", "documents", "photos", "references", "accounts", 'accounts', 'uuid_models'].sort, response.parsed_body.sort
  end

  test 'rendering null attribute' do
    property = create(:property)
    get property_path(property, format: 'json'), params: { id: property.id, include: [:landlord] }
    assert JSON(response.body).has_key?('landlord')
    assert_nil JSON(response.body)['landlord']
  end

  test 'rendering binary attribute' do
    reference = create(:reference, sha: "Hello World")
    get reference_path(reference, format: 'json'), params: { id: reference.id }
    assert_equal "48656c6c6f20576f726c64", JSON(response.body)['sha']
  end

  test 'rendering a custom binary attribute' do
    reference = create(:reference, custom_binary: 2)
    get reference_path(reference, format: 'json'), params: { id: reference.id }
    assert_equal 2, JSON(response.body)['custom_binary']
    assert_equal "\\x00000002".b,reference.custom_binary_before_type_cast
  end

  test 'rendering null attribute for has_one through' do
    property = create(:property)
    get property_path(property, format: 'json'), params: { id: property.id, include: [:document] }
    assert JSON(response.body).has_key?('document')
    assert_nil JSON(response.body)['document']
  end

  test 'rendering serialize_attribute' do
    property = create(:property, description: 'This text will magically change')
    get property_path(property, format: 'json'), params: { id: property.id, magic: true }

    body = JSON(response.body)
    assert_equal body['description'], 'See it changed!'
  end

  test 'rendering an enum' do
    public_document = create(:document, level: 'public')

    get documents_path(format: 'json'), params: { limit: 1 }
    assert_equal JSON(response.body)[0]['level'], 'public'

    secret_document = create(:document, level: 'secret')
    get document_path(secret_document, format: 'json')
    assert_equal JSON(response.body)['level'], 'secret'
  end

  test '#index.json uses overridden partial' do
    create(:property, photos: [create(:photo)])
    get properties_path(format: 'json'), params: { limit: 100, include: [{:photos => { order: :id }}] }

    photo = JSON(response.body)[0]['photos'][0]
    assert_equal true, photo.has_key?('template')
    assert_equal 'photos/_photo', photo['template']
  end

  test '#show.json uses overridden partial' do
    property = create(:property, photos: [create(:photo)])
    get property_path(property, format: 'json'), params: { id: property.id, include: [:photos] }

    photo = JSON(response.body)['photos'][0]
    assert_equal true, photo.has_key?('template')
    assert_equal 'photos/_photo', photo['template']
  end

  test '#schema.json uses overridden partial' do
    get schema_photos_path(format: 'json')

    schema = JSON(response.body)
    assert_rendered 'photos/schema', format: 'json', handler: 'jbuilder'
    assert_equal true, schema.has_key?('template')
    assert_equal 'photos/schema', schema['template']
  end

  test 'application#schema.json renders overridden #schema.json partials' do
    get schema_path(format: 'json')

    schema = JSON(response.body)
    assert_rendered 'application/schema', format: 'json', handler: 'jbuilder'
    assert_equal 'photos/schema', schema.dig('models', 'Photo', 'template')
  end

  test 'belongs_to polymorphic association' do
    photo = create(:photo)
    reference = create(:reference, subject: photo)
    get reference_path(reference, include: :subject, format: 'json')

    json = JSON(response.body)
    assert_equal 'photos/_photo', json['subject']['template']
  end

  test '#index.json includes polymorphic association' do
    property1 = create(:property)
    property2 = create(:property)
    photo = create(:photo)
    create(:reference, subject: property1)
    create(:reference, subject: property2)
    create(:reference, subject: photo)

    get references_path(format: 'json'), params: { include: [:subject], limit: 10 }

    json = JSON(response.body)
    assert_equal 'photos/_photo', json.find { |x| x['subject_type'] == "Photo"}['subject']['template']
  end

  test 'has_many association' do
    p = create(:property, photos: [create(:photo)])
    get properties_path(format: 'json'), params: { limit: 100, include: [:photos] }
    assert_equal p.photos.first.id, JSON(response.body)[0]['photos'][0]['id']
  end

  test 'belongs_to association' do
    account = create(:account)
    photo = create(:photo, account: account)
    get photo_path(photo, include: 'account', format: 'json')
    assert_equal account.id, JSON(response.body)['account']['id']
  end

  test 'has_one association' do
    account = create(:account)
    property = create(:property, landlord: account)
    get property_path(property, include: 'landlord', format: 'json')
    assert_equal account.id, JSON(response.body)['landlord']['id']
  end

  test 'include method' do
    property = create(:property)
    get property_path(property, include: 'english_name', format: 'json')
    assert_equal 'A Name', JSON(response.body)['english_name']
  end

  test 'include with where key' do
    photo_a = create(:photo)
    photo_b = create(:photo)
    photo_c = create(:photo)

    property = create(:property, photos: [photo_b, photo_c])
    get property_path(property, include: { photos: { where: { id: photo_a.id } } }, format: :json)
    assert_equal [], JSON(response.body)['photos']

    property.photos << photo_a
    get property_path(property, include: { photos: { where: { id: photo_a.id } } }, format: :json)
    assert_equal [photo_a.id], JSON(response.body)['photos'].map { |x| x['id'] }
    get property_path(property, include: { photos: { where: [
      { id: photo_a.id },
      'OR',
      { id: photo_c.id}
    ] } }, format: :json)
    assert_equal [photo_a.id, photo_c.id].sort,
      JSON(response.body)['photos'].map { |x| x['id'] }.sort
  end

  test 'include with order key' do
    photos = Array.new(5) { create(:photo) }
    property = create(:property, photos: photos)

    get property_path(property, include: { photos: { order: { id: :asc } } }, format: 'json')
    assert_equal photos.map(&:id).sort, JSON(response.body)['photos'].map { |x| x['id'] }
  end

  test 'include relation with default order using an order key' do
    p1 = create(:photo)
    p2 = create(:photo)
    account = create(:account, photos: [ p1, p2 ])
    get account_path(account, include: { photos: { order: { created_at: :desc } } }, format: 'json')
    assert_equal [ p2.id, p1.id ], JSON(response.body)['photos'].map { |x| x["id"] }
  end

  test 'include with limit key' do
    5.times { create(:property, photos: Array.new(5) { create(:photo) }) }
    get properties_path(include: { photos: { limit: 1 } }, limit: 5, format: 'json')

    properties = JSON(response.body)
    assert_equal 5, properties.length

    properties.each do |property|
      assert_equal 1, property['photos'].length
    end
  end

  test 'include with when key' do
    photo = create(:photo)
    account = create(:account, photos: [ photo ])
    account_reference = create(:reference, subject: account)

    property = create(:property, landlord: account)
    property_reference = create(:reference, subject: property)


    get references_path(
      include: {
        "subject" => {
          "landlord" => {
            "when" => {
              "subject_type" => 'Property'
            }
          },
          "photos" => {
            "when" => {
              "subject_type" => 'Account'
            }
          }
        }
      },
      limit: 20,
      format: 'json'
    )

    json = JSON(response.body)

    assert_equal photo.id, json.find { |x| x['id'] == account_reference.id }.dig('subject', 'photos', 0, 'id')
    assert_equal account.id, json.find { |x| x['id'] == property_reference.id }.dig('subject', 'landlord', 'id')
  end

  test 'include with distinct key' do
    account = create(:account)
    photos = Array.new(5) { create(:photo, account: account) }
    property = create(:property, photos: photos)

    get property_path(property, include: { photos: { distinct: true } }, format: 'json')
    assert_equal 5, JSON(response.body)['photos'].size
  end

  test 'include with distinct_on key' do
    account = create(:account)
    photos = Array.new(5) { create(:photo, account: account) }
    property = create(:property, photos: photos)

    get property_path(property,
      include: {
        photos: {
          distinct_on: :account_id,
          # order: [:account_id, { id: :asc }]
          order: { account_id: :asc, id: :asc }
        }
      },
      format: 'json')

    assert_equal [photos.map(&:id).sort.first], JSON(response.body)['photos'].map { |x| x['id'] }

    get property_path(property,
      include: {
        photos: {
          distinct_on: :account_id,
          order: { account_id: :asc, id: :desc }
        }
      }, format: 'json')

    assert_equal [photos.last.id], JSON(response.body)['photos'].map { |x| x['id'] }
  end

  test 'unknown inlcude' do
    property = create(:property, accounts: [ create(:account) ])
    get property_path(property, include: [:accounts], format: 'json')
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "accounts"', response.body
  end

  test 'unknown order' do
    create(:property)
    get properties_path(order: 'updated_at', limit: 1, format: 'json')
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "updated_at"', response.body
  end

  # Includes Test

  test 'Includes::normailze' do
    method = StandardAPI::Includes.method(:normalize)
    assert_equal method.call(:x), { 'x' => {} }
    assert_equal method.call([:x, :y]), { 'x' => {}, 'y' => {} }
    assert_equal method.call([ { x: true }, { y: true } ]), { 'x' => {}, 'y' => {} }
    assert_equal method.call({ x: true, y: true }), { 'x' => {}, 'y' => {} }
    assert_equal method.call({ x: { y: true } }), { 'x' => { 'y' => {} } }
    assert_equal method.call({ x: { y: {} } }), { 'x' => { 'y' => {} } }
    assert_equal method.call({ x: [:y] }), { 'x' => { 'y' => {} } }


    assert_equal method.call({ x: { where: { y: false } } }), { 'x' => { 'where' => { 'y' => false } } }
    assert_equal method.call({ x: { order: { y: :asc } } }), { 'x' => { 'order' => { 'y' => :asc } } }
  end

  # sanitize({:key => {}}, [:key]) # => {:key => {}}
  # sanitize({:key => {}}, {:key => true}) # => {:key => {}}
  # sanitize({:key => {}}, :value => {}}, [:key]) => # Raises ParseError
  # sanitize({:key => {}}, :value => {}}, {:key => true}) => # Raises ParseError
  # sanitize({:key => {:value => {}}}, {:key => [:value]}) # => {:key => {:value => {}}}
  # sanitize({:key => {:value => {}}}, {:key => {:value => true}}) # => {:key => {:value => {}}}
  # sanitize({:key => {:value => {}}}, [:key]) => # Raises ParseError
  test 'Includes::sanitize' do
    method = StandardAPI::Includes.method(:sanitize)
    assert_equal method.call(:x, [:x]), { 'x' => {} }
    assert_equal method.call(:x, {:x => true}), { 'x' => {} }

    assert_raises(StandardAPI::UnpermittedParameters) do
      method.call([:x, :y], [:x])
    end

    assert_raises(StandardAPI::UnpermittedParameters) do
      method.call([:x, :y], {:x => true})
    end

    assert_raises(StandardAPI::UnpermittedParameters) do
      method.call({:x => true, :y => true}, [:x])
    end
    assert_raises(StandardAPI::UnpermittedParameters) do
      method.call({:x => true, :y => true}, {:x => true})
    end
    assert_raises(StandardAPI::UnpermittedParameters) do
      method.call({ x: { y: true }}, { x: true })
    end

    assert_equal method.call({ x: { y: true }}, { x: { y: true } }), { 'x' => { 'y' => {} } }
  end

  # Order Test

  test 'Orders::sanitize(:column, [:column])' do
    method = StandardAPI::Orders.method(:sanitize)

    assert_equal :x, method.call(:x, :x)
    assert_equal :x, method.call(:x, [:x])
    assert_equal :x, method.call([:x], [:x])
    assert_raises(StandardAPI::UnpermittedParameters) do
      method.call(:x, :y)
    end

    assert_equal({ x: :asc }, method.call({ x: :asc }, :x))
    assert_equal({ x: :desc }, method.call({ x: :desc }, :x))
    assert_equal([{ x: :desc}, {y: :desc }], method.call({ x: :desc, y: :desc }, [:x, :y]))
    assert_equal({ x: :asc }, method.call([{ x: :asc }], :x))
    assert_equal({ x: :desc }, method.call([{ x: :desc }], :x))
    assert_equal({ x: { asc: :nulls_last } }, method.call([{ x: { asc: :nulls_last } }], :x))
    assert_equal({ x: { asc: :nulls_first } }, method.call([{ x: { asc: :nulls_first } }], :x))
    assert_equal({ x: { desc: :nulls_last } }, method.call([{ x: { desc: :nulls_last } }], :x))
    assert_equal({ x: { desc: :nulls_first }}, method.call([{ x: { desc: :nulls_first } }], :x))
    assert_equal({ relation: :id }, method.call(['relation.id'], { relation: :id }))
    assert_equal({ relation: :id }, method.call([{ relation: :id }], { relation: :id }))
    assert_equal({ relation: :id }, method.call([{ relation: :id }], [{ relation: :id }]))
    assert_equal({ relation: :id }, method.call([{ relation: [:id] }], { relation: [:id] }))
    assert_equal({ relation: :id }, method.call([{ relation: [:id] }], [{ relation: [:id] }]))
    assert_equal({ relation: { id: :desc } }, method.call([{'relation.id' => :desc}], { relation: :id }))
    assert_equal({ relation: { id: :desc } }, method.call([{ relation: { id: :desc } }], { relation: [:id] }))
    assert_equal({ relation: { id: :desc } }, method.call([{ relation: { id: :desc } }], [{ relation: [:id] }]))
    assert_equal({ relation: { id: :desc } }, method.call([{ relation: [{ id: :desc }] }], [{ relation: [:id] }]))
    assert_equal({ relation: { id: :desc } }, method.call([{ relation: [{ id: :desc }] }], [{ relation: [:id] }]))
    assert_equal({ relation: {:id => {:asc => :nulls_last}} }, method.call([{ relation: {:id => {:asc => :nulls_last}} }], [{ relation: [:id] }]))
    assert_equal({ relation: {:id => {:asc => :nulls_last}} }, method.call([{ relation: {:id => {:asc => :nulls_last}} }], [{ relation: [:id] }]))
    assert_equal({ relation: {:id => [{:asc => :nulls_last}]} }, method.call([{ relation: {:id => [{:asc => :nulls_last}]} }], [{ relation: [:id] }]))
    assert_equal({ relation: {:id => [{:asc => :nulls_last}]} }, method.call([{ relation: {:id => [{:asc => :nulls_last}]} }], [{ relation: [:id] }]))
  end

  test 'order: :attribute' do
    properties = Array.new(2) { create(:property) }

    get properties_path(order: :id, limit: 100, format: 'json')
    assert_equal properties.map(&:id).sort, JSON(response.body).map { |x| x['id'] }
  end

  test 'order: { attribute: :direction }' do
    properties = Array.new(2) { create(:property) }

    get properties_path(order: { id: :asc }, limit: 100, format: 'json')
    assert_equal properties.map(&:id).sort, JSON(response.body).map { |x| x['id'] }

    get properties_path(order: { id: :desc }, limit: 100, format: 'json')
    assert_equal properties.map(&:id).sort.reverse, JSON(response.body).map { |x| x['id'] }
  end

  test 'order: { attribute: { direction: :nulls } }' do
    properties = [ create(:property), create(:property, description: nil) ]

    get properties_path(order: { description: { asc: :nulls_last } }, limit: 100, format: 'json')
    assert_equal properties.map(&:id).sort, JSON(response.body).map { |x| x['id'] }

    get properties_path(order: { description: { asc: :nulls_first } }, limit: 100, format: 'json')
    assert_equal properties.map(&:id).sort.reverse, JSON(response.body).map { |x| x['id'] }
  end

  test 'ordering via nulls_first/last' do
    p1 = create(:property, description: 'test')
    p2 = create(:property, description: nil)

    get properties_path(format: 'json'), params: { limit: 100, order: { description: { desc: 'nulls_last' } } }
    properties = JSON(response.body)
    assert_equal p1.id, properties.first['id']

    get properties_path(format: 'json'), params: { limit: 100, order: { description: { asc: 'nulls_last' } } }
    properties = JSON(response.body)
    assert_equal p1.id, properties.first['id']
  end

  # Calculate Test
  test 'calculate' do
    create(:photo)
    get '/photos/calculate', params: {select: {count: "*"}}
    assert_equal [1], JSON(response.body)
  end

  test 'calculate distinct aggregation' do
    assert_sql(<<-SQL) do
      SELECT DISTINCT COUNT("properties"."id") FROM "properties"
    SQL
      create(:property)
      create(:property)
      get '/properties/calculate', params: {
        select: { count: "id" },
        distinct: true
      }
      assert_equal [2], JSON(response.body)
    end
  end

  test 'calculate aggregation distinctly' do
    assert_sql(<<-SQL) do
      SELECT COUNT(DISTINCT "properties"."id") FROM "properties"
    SQL
      create(:property)
      create(:property)
      get '/properties/calculate', params: {
        select: { count: { distinct: "id" } }
      }
      assert_equal [2], JSON(response.body)
    end
  end

  test 'calculate distinct aggregation distinctly' do
    assert_sql(<<-SQL) do
      SELECT DISTINCT COUNT(DISTINCT "properties"."id") FROM "properties"
    SQL
      create(:property)
      create(:property)
      get '/properties/calculate', params: {
        select: { count: { distinct: "id" } },
        distinct: true
      }
      assert_equal [2], JSON(response.body)
    end
  end

  test 'calculate distinct count' do
    p1 = create(:property)
    p2 = create(:property)
    a1 = create(:account, property: p1)
    a2 = create(:account, property: p2)
    get '/properties/calculate', params: {
      select: { count: 'id' },
      where: {
        accounts: {
          id: [a1.id, a2.id]
        }
      },
      group_by: 'id',
      distinct: true
    }
    assert_equal Hash[p1.id.to_s, 1, p2.id.to_s, 1], JSON(response.body)
  end

  test 'calculate group_by' do
    create(:photo, format: 'jpg')
    create(:photo, format: 'jpg')
    create(:photo, format: 'png')
    get '/photos/calculate', params: {select: {count: "*"}, group_by: 'format'}
    assert_equal ({'png' => 1, 'jpg' => 2}), JSON(response.body)
  end

  test 'calculate join' do
    p1 = create(:property)
    p2 = create(:property)
    create(:account, photos_count: 1, property: p1)
    create(:account, photos_count: 2, property: p2)

    get '/properties/calculate', params: {select: {sum: "accounts.photos_count"}, join: 'accounts'}
    assert_equal [3], JSON(response.body)
  end

  test 'calculate count distinct' do
    photo = create(:photo)
    landlord = create(:account)
    create(:property, landlord: landlord, photos: [photo])
    create(:property, landlord: landlord, photos: [photo])

    get '/photos/calculate', params: {select: {count: "*"},
      where: {properties: {landlord: {id: landlord.id}}},
      distinct: true
    }

    assert_equal [1], JSON(response.body)
  end

  test 'preloading polymorphic associations' do
    p1 = create(:property)
    p2 = create(:property)
    c1 = create(:camera)
    c2 = create(:camera)
    a1 = create(:account, subject: p1, subject_cached_at: Time.now)
    a2 = create(:account, subject: p2, subject_cached_at: Time.now)
    a3 = create(:account, subject: c1, subject_cached_at: Time.now)
    a4 = create(:account, subject: c2, subject_cached_at: Time.now)
    a5 = create(:account, subject: c2, subject_cached_at: Time.now)

    assert_sql(
      'SELECT "properties".* FROM "properties" WHERE "properties"."id" IN ($1, $2)',
      'SELECT "cameras".* FROM "cameras" WHERE "cameras"."id" IN ($1, $2)'
    ) do
      assert_no_sql("SELECT \"properties\".* FROM \"properties\" WHERE \"properties\".\"id\" = $1 LIMIT $2") do
        get accounts_path(limit: 10, include: { subject: { landlord: { when: { subject_type: 'Property' } } } }, format: 'json')

        assert_equal p1.id, a1.subject_id
        assert_equal p2.id, a2.subject_id
        assert_equal c1.id, a3.subject_id
        assert_equal p1.id, JSON(response.body).dig(0, 'subject', 'id')
        assert_equal p2.id, JSON(response.body).dig(1, 'subject', 'id')
        assert_equal c1.id, JSON(response.body).dig(2, 'subject', 'id')
        assert_equal c2.id, JSON(response.body).dig(3, 'subject', 'id')
        assert_equal c2.id, JSON(response.body).dig(4, 'subject', 'id')
      end
    end
  end



end
