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

  test 'include StandardAPI includes Controller and Policies' do
    klass = Class.new(ActionController::Base) do
      include StandardAPI
    end
    assert klass.ancestors.include?(StandardAPI::Controller), "Expected StandardAPI::Controller to be included"
    assert klass.ancestors.include?(StandardAPI::Policies), "Expected StandardAPI::Policies to be included"
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

  test 'Policy::Record#orderable is [] when the Policy makes nothing orderable' do
    assert_equal [], ReferencesController.new.record_policy(Reference).orderable
  end

  test "Policy::Record#orderable falls back to the base class's Policy" do
    assert_equal ['id'], DocumentsController.new.record_policy(Pdf).orderable
  end

  test "TestCase#where_permitted? checks what the Policy makes filterable" do
    assert where_permitted?({ id: 1 })
    assert_not where_permitted?({ name: 'a' })
  end

  test "Policy::Record#filterable falls back to the base class's Policy" do
    with_model_policy(Document, Class.new(DocumentPolicy) { attribute :id, filterable: true }) do
      assert_equal({ 'id' => :all }, DocumentsController.new.record_policy(Pdf).filterable)
    end
  end

  test "Policy#declared_includes is what the Policy declares can be included" do
    includes = AccountPolicy.new(AccountsController.new, Account).declared_includes
    assert_equal %w[photos property subject], includes.keys.sort
    assert_equal [Property], includes['subject'][:types]
    assert_nil includes['photos'][:policy]
  end

  test "Includes#sanitize_includes checks an STI subclass against its base class's Policy" do
    sanitize = -> { DocumentsController.new.send(:sanitize_includes, :file, Pdf) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call }

    # file is a method of Document
    policies = ApplicationController.standard_api_policies.merge('document' => Class.new(DocumentPolicy) { association :file })
    ApplicationController.stubs(:standard_api_policies).returns(policies)
    assert_equal({ 'file' => {} }, sanitize.call)
  ensure
    ApplicationController.unstub(:standard_api_policies)
  end

  test 'Includes#sanitize_includes permits nothing without a model or Policy' do
    assert_raises(StandardAPI::UnpermittedParameters) do
      DocumentsController.new.send(:sanitize_includes, :anything, nil)
    end
    assert_equal({ 'limit' => 1 }, DocumentsController.new.send(:sanitize_includes, { limit: 1 }, nil))
  end

  test 'Controller#model_params defaults to ActionController::Parameters' do
    @controller = DocumentsController.new
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

  test 'Policy::Record#writable is decided for the record, a model being a create' do
    controller = DocumentsController.new

    assert_equal ['type', 'file'], controller.record_policy(Document).writable
    assert_equal ['type', 'file', 'rating'], controller.record_policy(create(:document, type: 'movie')).writable
  end

  test 'Policy::Record#writable is empty when the Policy makes nothing writable' do
    assert_equal [], ReferencesController.new.record_policy(Reference).writable
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

    @controller.send(:models).reject { |x| %w(Photo Document Note).include?(x.name)  }.each do |model|
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
          cast_type = if column.respond_to?(:fetch_cast_type)
            column.fetch_cast_type(model.connection)
          elsif column.respond_to?(:cast_type)
            column.cast_type
          else
            model.connection.lookup_cast_type_from_column(column)
          end
          default = cast_type.deserialize(default)
          assert_equal default, schema.dig('models', model.name, 'attributes', column.name, 'default')
        else
          assert_nil schema.dig('models', model.name, 'attributes', column.name, 'default')
        end
        assert_equal column.name == model.primary_key, schema.dig('models', model.name, 'attributes', column.name, 'primary_key')
        assert_equal column.null, schema.dig('models', model.name, 'attributes', column.name, 'null')
        assert_equal column.array, schema.dig('models', model.name, 'attributes', column.name, 'array')
        # CamerasController::Policy declares a comment of its own
        comment = model == Camera && column.name == 'make' ? 'The manufacturer' : column.comment
        if comment
          assert_equal comment, schema.dig('models', model.name, 'attributes', column.name, 'comment')
        else
          assert_nil schema.dig('models', model.name, 'attributes', column.name, 'comment')
        end

        assert_equal !!column.auto_populated?, schema.dig('models', model.name, 'attributes', column.name, 'auto_populated')
      end
    end

    assert_equal true, schema['models']['Account']['attributes']['id']['readonly']
    assert_equal false, schema['models']['Account']['attributes']['name']['readonly']
    # ReferencePolicy makes nothing writable
    assert_equal true, schema['models']['Reference']['attributes']['key']['readonly']

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

    # Only mariadb and postgresql support comments on databases
    assert_equal('test comment', schema['comment']) if postgres? || mariadb?
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
    assert_equal ["properties", "accounts", "cameras", "documents", "notes", "photos", "references", "accounts", 'accounts', 'uuid_models'].sort, response.parsed_body.sort
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
    assert_equal "\\x00000002".b, reference.custom_binary_before_type_cast if postgres?
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

  test 'mask_for is applied to included associations' do
    property = create(:property, photos: [create(:photo, format: 'jpg'), create(:photo, format: 'png')])

    # Mask the included photos to jpg only; the include should respect it just
    # like the top-level query would.
    PropertiesController.send(:define_method, :mask_for) do |table_name|
      table_name == :photos ? { format: 'jpg' } : nil
    end

    get properties_path(format: 'json'), params: { limit: 100, include: [:photos] }
    photos = JSON(response.body).find { |x| x['id'] == property.id }['photos']
    assert_equal ['jpg'], photos.map { |x| x['format'] }
  ensure
    PropertiesController.send(:remove_method, :mask_for)
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

  test 'include with when key renders the include only for matching records' do
    photo = create(:photo)
    matching = create(:property, name: 'a', photos: [photo])
    other = create(:property, name: 'b', photos: [create(:photo)])

    with_model_policy(Property, Class.new(PropertyPolicy) { attribute :name, filterable: true }) do
      get properties_path(format: 'json'), params: { limit: 10, include: { photos: { when: { name: 'a' } } } }
    end
    assert_response :ok
    json = JSON(response.body).index_by { |x| x['id'] }
    assert_equal [photo.id], json[matching.id]['photos'].map { |x| x['id'] }
    assert_not json[other.id].has_key?('photos')
  end

  test 'include with when key only reads attributes' do
    create(:property, photos: [create(:photo)])

    # A method, not an attribute, is never called
    get properties_path(format: 'json'), params: { limit: 10, include: { photos: { when: { destroy: '1' } } } }
    assert_response :bad_request
    assert_equal 1, Property.count

    # A nested when is checked against the model of the records it's on
    get properties_path(format: 'json'), params: { limit: 10, include: { photos: { account: { when: { destroy: '1' } } } } }
    assert_response :bad_request

    # An attribute PropertyPolicy doesn't make filterable
    get properties_path(format: 'json'), params: { limit: 10, include: { photos: { when: { name: 'x' } } } }
    assert_response :bad_request
  end

  test 'Includes#check_include_when permits attributes, including aliases and the attributes API' do
    klass = Class.new(Property) do
      alias_attribute :title, :name
      attribute :featured, :boolean
      def self.name = 'Property'
    end
    controller = PropertiesController.new
    policy = Class.new(PropertyPolicy) { filterable :name, :title, :featured }
    controller.stubs(:model_policy).returns(policy.new(controller, klass))
    check = controller.method(:check_include_when)

    assert_nothing_raised { check.call('photos', { 'name' => 'a', 'title' => 'a', 'featured' => true }, klass) }
    assert_raises(StandardAPI::UnpermittedParameters) { check.call('photos', { 'destroy' => '1' }, klass) }
    assert_raises(StandardAPI::UnpermittedParameters) { check.call('photos', 'name', klass) }
    # Under a polymorphic association there is no model to check against
    assert_nothing_raised { check.call('photos', { 'destroy' => '1' }, nil) }
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

  test 'include with where key rejects wheres the included Policy does not permit' do
    property = create(:property, photos: [create(:photo)])

    # PhotoPolicy doesn't make format filterable
    get property_path(property, include: { photos: { where: { format: 'jpg' } } }, format: :json)
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "format"', response.body

    get property_path(property, include: { photos: { where: [{ id: 1 }, 'OR', { format: 'jpg' }] } }, format: :json)
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "format"', response.body
  end

  test 'include with where key under a polymorphic association is rejected' do
    create(:account, subject: create(:property))

    get "/accounts", params: { limit: 10, include: { subject: { where: { id: 1 } } } }, as: :json
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "where"', response.body
  end

  test 'include with order key' do
    photos = Array.new(5) { create(:photo) }
    property = create(:property, photos: photos)

    get property_path(property, include: { photos: { order: { id: :asc } } }, format: 'json')
    assert_equal photos.map(&:id).sort, JSON(response.body)['photos'].map { |x| x['id'] }
  end

  test "include with order key rejects orders the included model's Policy doesn't make orderable" do
    property = create(:property, photos: [create(:photo)])

    # PhotoPolicy doesn't make format orderable
    get property_path(property, include: { photos: { order: { format: :asc } } }, format: 'json')
    assert_response :bad_request

    get property_path(property, include: { photos: { order: ['(SELECT 1) DESC'] } }, format: 'json')
    assert_response :bad_request
  end

  test "include with order key through an association uses the associated model's Policy" do
    b = create(:photo, account: create(:account, name: 'b'))
    a = create(:photo, account: create(:account, name: 'a'))
    property = create(:property, photos: [b, a])

    with_model_policy(Photo, Class.new(PhotoPolicy) { association :account, orderable: true }) do
      get property_path(property, include: { photos: { order: { account: { id: :desc } } } }, format: 'json')
    end
    assert_response :ok
    assert_equal [a.id, b.id], JSON(response.body)['photos'].map { |x| x['id'] }
  end

  test 'include with order key under a polymorphic association is rejected' do
    create(:account, subject: create(:property))

    get "/accounts", params: { limit: 10, include: { subject: { order: { id: :asc } } } }, as: :json
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "order"', response.body
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
    skip "DISTINCT ON is a Postgres-only SQL feature" unless postgres?

    account = create(:account)
    photos = Array.new(5) { create(:photo, account: account) }
    property = create(:property, photos: photos)

    get property_path(property,
      include: {
        photos: {
          distinct_on: :account_id,
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
    property = create(:property)
    get property_path(property, include: [:document_attachments], format: 'json')
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "document_attachments"', response.body
  end

  test 'unknown order' do
    create(:property)
    get properties_path(order: 'updated_at', limit: 1, format: 'json')
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "updated_at"', response.body
  end

  test 'order through an association uses the associated Policy' do
    b = create(:account, property: create(:property, name: 'b'))
    a = create(:account, property: create(:property, name: 'a'))

    get accounts_path(order: { property: { name: :asc } }, limit: 10, format: 'json')
    assert_response :ok
    assert_equal [a.id, b.id], JSON(response.body).map { |x| x['id'] }

    get accounts_path(order: { property: { name: :desc } }, limit: 10, format: 'json')
    assert_response :ok
    assert_equal [b.id, a.id], JSON(response.body).map { |x| x['id'] }

    get accounts_path(order: 'property.name', limit: 10, format: 'json')
    assert_response :ok
    assert_equal [a.id, b.id], JSON(response.body).map { |x| x['id'] }
  end

  test 'order through an association rejects orders ActiveRecord::Sort can not order by' do
    create(:account, property: create(:property))

    # ActiveRecord::Sort only orders one association deep
    with_model_policy(Property, Class.new(PropertyPolicy) { association :landlord, orderable: true }) do
      get accounts_path(order: { property: { landlord: { id: :asc } } }, limit: 10, format: 'json')
    end
    assert_response :bad_request
    assert_equal 'Unknown column landlord', response.body
  end

  test "order through an association rejects orders the associated model's Policy doesn't make orderable" do
    create(:account, property: create(:property))

    get accounts_path(order: { property: { updated_at: :asc } }, limit: 10, format: 'json')
    assert_response :bad_request

    get accounts_path(order: 'property.updated_at', limit: 10, format: 'json')
    assert_response :bad_request
  end

  # A stand-in Policy::Record that makes +permit+ orderable on +model+
  def orderable_policy(model, permit)
    Struct.new(:model, :orderable).new(model, permit)
  end

  test 'Orders#sanitize_orders rejects ordering through a polymorphic association' do
    sanitize = AccountsController.new.method(:sanitize_orders)

    assert_raises(StandardAPI::UnpermittedParameters) do
      sanitize.call({ subject: { id: :asc } }, orderable_policy(Account, [:subject]))
    end
  end

  test 'include through an association uses the associated Policy' do
    property = create(:property)
    account = create(:account, property: property)
    photo = create(:photo, account: account)

    get property_path(property, include: { landlord: :photos }, format: 'json')
    assert_response :ok
    assert_equal account.id, JSON(response.body)['landlord']['id']
    assert_equal [photo.id], JSON(response.body)['landlord']['photos'].map { |x| x['id'] }
  end

  test 'include through an association rejects includes the associated Policy does not permit' do
    property = create(:property, photos: [create(:photo)])

    get property_path(property, include: { photos: :camera }, format: 'json')
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "camera"', response.body
  end

  test 'include through two associations uses each associated Policy' do
    account = create(:account)
    camera = create(:camera, photo: create(:photo, account: account))

    get "/cameras/#{camera.id}", params: { include: { photo: :account } }, as: :json
    assert_response :ok
    assert_equal account.id, JSON(response.body)['photo']['account']['id']
  end

  test "a polymorphic association's types permit what their Policies declare" do
    sanitize = ->(includes) { AccountsController.new.send(:sanitize_includes, includes, Account) }

    # AccountPolicy declares subject with types: ['Property']
    assert_equal({ 'subject' => { 'landlord' => { 'photos' => {} } } }, sanitize.call({ subject: { landlord: :photos } }))
    assert_equal({ 'subject' => { 'limit' => 1 } }, sanitize.call({ subject: { limit: 1 } }))
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: :document_attachments }) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { where: { id: 1 } } }) }
  end

  test "a polymorphic association's includes can each come from a different type" do
    policies = ApplicationController.standard_api_policies.merge('account' => Class.new(AccountPolicy) { association :subject, types: [Property, Photo] })
    ApplicationController.stubs(:standard_api_policies).returns(policies)
    sanitize = ->(includes) { AccountsController.new.send(:sanitize_includes, includes, Account) }

    # landlord is PropertyPolicy's and account PhotoPolicy's
    assert_equal({ 'subject' => { 'landlord' => {}, 'account' => {} } }, sanitize.call({ subject: [:landlord, :account] }))
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: :camera }) }
  ensure
    ApplicationController.unstub(:standard_api_policies)
  end

  # A Reference's subject can be an Account or a Property, which both declare
  # owner: Account#owner is a Property, whose Policy makes name filterable and
  # orderable and declares landlord, and Property#owner an Account, whose
  # Policy doesn't. +owner_policy+ is the policy Property#owner gives, if any.
  def with_owner_policies(owner_policy = nil)
    policies = ApplicationController.standard_api_policies.merge(
      'reference' => Class.new(ReferencePolicy) { association :subject, types: [Account, Property] },
      'account' => Class.new(AccountPolicy) { association :owner },
      'property' => Class.new(PropertyPolicy) do
        filterable :name
        association :owner, policy: owner_policy
      end
    )
    ApplicationController.stubs(:standard_api_policies).returns(policies)
    yield ->(includes) { ReferencesController.new.send(:sanitize_includes, includes, Reference) }
  ensure
    ApplicationController.unstub(:standard_api_policies)
  end

  test "a polymorphic association's include is checked against every type that declares it" do
    with_owner_policies do |sanitize|
      # Both make id filterable and orderable
      assert_equal({ 'subject' => { 'owner' => { 'where' => { 'id' => 1 } } } }, sanitize.call({ subject: { owner: { where: { id: 1 } } } }))
      assert_nothing_raised { sanitize.call({ subject: { owner: { order: { id: :asc } } } }) }

      # PropertyPolicy permits them, but they'd also filter and order the
      # Account owners of Property subjects
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { owner: { where: { name: 'x' } } } }) }
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { owner: { order: { name: :asc } } } }) }
    end
  end

  test "a polymorphic association's include is rejected if what's below it is declared by only some of the types declaring it" do
    with_owner_policies do |sanitize|
      # PropertyPolicy and AccountPolicy declare photos, only PropertyPolicy
      # landlord, and the owners, Properties and Accounts, are preloaded
      # together
      assert_equal({ 'subject' => { 'owner' => { 'photos' => {} } } }, sanitize.call({ subject: { owner: :photos } }))
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { owner: :landlord } }) }
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { owner: :document_attachments } }) }
    end
  end

  test "a polymorphic association's includes declared by only one type are permitted" do
    with_owner_policies do |sanitize|
      # landlord is PropertyPolicy's and property AccountPolicy's
      assert_equal({ 'subject' => { 'landlord' => { 'photos' => {} }, 'property' => {} } }, sanitize.call({ subject: { landlord: :photos, property: true } }))
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: :document_attachments }) }
    end
  end

  test "a polymorphic association's include is checked against each type's association policy" do
    through = Class.new(StandardAPI::Policy) do
      attributes :id, :name
      attribute :name, filterable: true
    end

    with_owner_policies(through) do |sanitize|
      assert_nothing_raised { sanitize.call({ subject: { owner: { where: { name: 'x' } } } }) }
      # Property#owner's policy doesn't make id filterable
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { owner: { where: { id: 1 } } } }) }
    end
  end

  test "a polymorphic association's include every type declaring it permits is rendered" do
    property = create(:property)
    account = create(:account, property: property)
    landlord = create(:account, property: create(:property))
    account_reference = create(:reference, subject: account)
    property_reference = create(:reference, subject: landlord.property)

    with_owner_policies do
      get references_path(include: { subject: { owner: :photos } }, limit: 20, format: 'json')
    end
    assert_response :ok

    json = JSON(response.body)
    assert_equal property.id, json.find { |x| x['id'] == account_reference.id }.dig('subject', 'owner', 'id')
    assert_equal property.photos.map(&:id), json.find { |x| x['id'] == account_reference.id }.dig('subject', 'owner', 'photos').map { |x| x['id'] }
    assert_equal landlord.id, json.find { |x| x['id'] == property_reference.id }.dig('subject', 'owner', 'id')
    assert_equal [], json.find { |x| x['id'] == property_reference.id }.dig('subject', 'owner', 'photos')
  end

  test "a polymorphic association's include only some types have below it is a 400, not a preload error" do
    property = create(:property)
    create(:reference, subject: create(:account, property: property))
    create(:reference, subject: create(:account, property: create(:property)).property)

    with_owner_policies do
      # The owners, Properties and Accounts, would be preloaded together,
      # and Account has no landlord
      get references_path(include: { subject: { owner: :landlord } }, limit: 20, format: 'json')
    end
    assert_response :bad_request
  end

  test 'types must be models or their names' do
    assert_raises(ArgumentError) { Class.new(StandardAPI::Policy) { association :subject, types: [:property] } }
  end

  test "Includes#sanitize_includes checks an association's includes against its model's Policy" do
    sanitize = ->(includes) { PropertiesController.new.send(:sanitize_includes, includes, Property) }

    # PropertyPolicy declares landlord, an Account, and AccountPolicy photos
    assert_equal({ 'landlord' => { 'photos' => {} } }, sanitize.call({ landlord: :photos }))
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ landlord: :agents }) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ document_attachments: true }) }
  end

  test "Includes#sanitize_includes checks an association's includes against its policy" do
    through = Class.new(StandardAPI::Policy) { associations :property }
    policy = Class.new(PropertyPolicy) { association :landlord, policy: through }
    controller = PropertiesController.new
    controller.stubs(:model_policy).with(Property).returns(policy.new(controller, Property))

    assert_equal({ 'landlord' => { 'property' => {} } }, controller.send(:sanitize_includes, { landlord: :property }, Property))
    assert_raises(StandardAPI::UnpermittedParameters) do
      controller.send(:sanitize_includes, { landlord: :photos }, Property)
    end
  end

  # The Policies of a Property whose landlord, an Account, is included with
  # +landlord_policy+
  def stub_landlord_policy(controller, landlord_policy)
    policy = Class.new(PropertyPolicy) { association :landlord, policy: landlord_policy }
    controller.stubs(:model_policy).with(Property).returns(policy.new(controller, Property))
    controller.stubs(:model_policy).with(Account).returns(AccountPolicy.new(controller, Account))
    controller.stubs(:model_policy).with(Photo).returns(PhotoPolicy.new(controller, Photo))
  end

  test "Includes#sanitize_includes checks an include's where, order and when against its policy" do
    # AccountPolicy makes id filterable and orderable, not name
    through = Class.new(StandardAPI::Policy) do
      attributes :id, :name
      attribute :name, filterable: true, orderable: true
      association :photos
    end
    controller = PropertiesController.new
    stub_landlord_policy(controller, through)
    sanitize = ->(includes) { controller.send(:sanitize_includes, includes, Property) }

    assert_nothing_raised { sanitize.call({ landlord: { where: { name: 'a' } } }) }
    assert_nothing_raised { sanitize.call({ landlord: { order: { name: :asc } } }) }
    assert_nothing_raised { sanitize.call({ landlord: { photos: { when: { name: 'a' } } } }) }

    # What only the model's Policy permits isn't what the landlord renders with
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ landlord: { where: { id: 1 } } }) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ landlord: { order: { id: :asc } } }) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ landlord: { photos: { when: { id: 1 } } } }) }
  end

  test "Includes#sanitize_includes checks an include's where and order against what its policy gives for a model" do
    through = Class.new(StandardAPI::Policy) do
      attributes :id, :name
      attribute :name, filterable: true, orderable: true
    end
    sanitize = ->(landlord_policy, includes) do
      controller = PropertiesController.new
      stub_landlord_policy(controller, landlord_policy)
      controller.send(:sanitize_includes, includes, Property)
    end

    # A Proc is called with a nil record, as none is loaded yet
    assert_nothing_raised { sanitize.call(-> { through }, { landlord: { where: { name: 'a' } } }) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call(-> { through }, { landlord: { where: { id: 1 } } }) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call(-> { through }, { landlord: { order: { id: :asc } } }) }

    # When it gives none, the model's Policy
    assert_nothing_raised { sanitize.call(-> { nil }, { landlord: { where: { id: 1 } } }) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call(-> { nil }, { landlord: { where: { name: 'a' } } }) }
  end

  test "Orders#sanitize_orders checks an association permitted by name against its model's Policy" do
    # AccountPolicy makes id orderable, not name
    sanitize = PropertiesController.new.method(:sanitize_orders)

    assert_equal({ landlord: { id: :asc } }, sanitize.call({ landlord: { id: :asc } }, orderable_policy(Property, [:landlord])))
    assert_equal({ landlord: :id }, sanitize.call('landlord.id', orderable_policy(Property, [:landlord])))
    assert_raises(StandardAPI::UnpermittedParameters) do
      sanitize.call({ landlord: { name: :asc } }, orderable_policy(Property, [:landlord]))
    end

    # A column is unchanged
    assert_equal({ name: :desc }, sanitize.call({ name: :desc }, orderable_policy(Property, [:name])))
  end

  test 'Orders#sanitize_orders rejects ordering through an association whose model has nothing orderable' do
    sanitize = PropertiesController.new.method(:sanitize_orders)

    with_model_policy(Account, Class.new(AccountPolicy) { attribute :id, orderable: false }) do
      assert_raises(StandardAPI::UnpermittedParameters) do
        sanitize.call({ landlord: { id: :asc } }, orderable_policy(Property, [:landlord]))
      end
      assert_raises(StandardAPI::UnpermittedParameters) do
        sanitize.call('landlord.id', orderable_policy(Property, [:landlord]))
      end
    end
  end

  # Includes Test

  test 'Includes#normalize_includes' do
    method = PropertiesController.new.method(:normalize_includes)
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

  # sanitize_includes({:key => {}}, [:key]) # => {:key => {}}
  # sanitize_includes({:key => {}}, {:key => true}) # => {:key => {}}
  # sanitize_includes({:key => {}}, :value => {}}, [:key]) => # Raises ParseError
  # sanitize_includes({:key => {}}, :value => {}}, {:key => true}) => # Raises ParseError
  # sanitize_includes({:key => {:value => {}}}, {:key => [:value]}) # => {:key => {:value => {}}}
  # sanitize_includes({:key => {:value => {}}}, {:key => {:value => true}}) # => {:key => {:value => {}}}
  # sanitize_includes({:key => {:value => {}}}, [:key]) => # Raises ParseError
  test 'Includes#sanitize_includes' do
    method = ->(includes) { PropertiesController.new.send(:sanitize_includes, includes, Property) }
    assert_equal({ 'photos' => {}, 'landlord' => {} }, method.call([:photos, :landlord]))
    assert_equal({ 'photos' => { 'account' => {} } }, method.call({ photos: { account: true } }))

    assert_raises(StandardAPI::UnpermittedParameters) { method.call(:x) }
    assert_raises(StandardAPI::UnpermittedParameters) { method.call([:photos, :x]) }
    # PhotoPolicy declares account, not property
    assert_raises(StandardAPI::UnpermittedParameters) { method.call({ photos: { property: true } }) }
  end

  # Order Test

  test 'Orders#sanitize_orders(:column, [:column])' do
    method = ->(orders, permit) { AccountsController.new.send(:sanitize_orders, orders, orderable_policy(Account, permit)) }

    assert_equal :name, method.call(:name, [:name])
    assert_equal :name, method.call(:name, [:name])
    assert_equal :name, method.call([:name], [:name])
    assert_raises(StandardAPI::UnpermittedParameters) do
      method.call(:name, [:id])
    end

    assert_equal({ name: :asc }, method.call({ name: :asc }, [:name]))
    assert_equal({ name: :desc }, method.call({ name: :desc }, [:name]))
    assert_equal([{ name: :desc}, {id: :desc }], method.call({ name: :desc, id: :desc }, [:name, :id]))
    assert_equal({ name: :asc }, method.call([{ name: :asc }], [:name]))
    assert_equal({ name: :desc }, method.call([{ name: :desc }], [:name]))
    assert_equal({ name: { asc: :nulls_last } }, method.call([{ name: { asc: :nulls_last } }], [:name]))
    assert_equal({ name: { asc: :nulls_first } }, method.call([{ name: { asc: :nulls_first } }], [:name]))
    assert_equal({ name: { desc: :nulls_last } }, method.call([{ name: { desc: :nulls_last } }], [:name]))
    assert_equal({ name: { desc: :nulls_first }}, method.call([{ name: { desc: :nulls_first } }], [:name]))

    # Through an association, checked against PropertyPolicy
    assert_equal({ property: :id }, method.call(['property.id'], [:property]))
    assert_equal({ property: :id }, method.call([{ property: :id }], [:property]))
    assert_equal({ property: :id }, method.call([{ property: [:id] }], [:property]))
    assert_equal({ property: { id: :desc } }, method.call([{'property.id' => :desc}], [:property]))
    assert_equal({ property: { id: :desc } }, method.call([{ property: { id: :desc } }], [:property]))
    assert_equal({ property: { id: :desc } }, method.call([{ property: [{ id: :desc }] }], [:property]))
    assert_equal({ property: {:id => {:asc => :nulls_last}} }, method.call([{ property: {:id => {:asc => :nulls_last}} }], [:property]))
    assert_equal({ property: {:id => [{:asc => :nulls_last}]} }, method.call([{ property: {:id => [{:asc => :nulls_last}]} }], [:property]))
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
    skip "NULLS FIRST/LAST ordering is only implemented for Postgres by arel-extensions" unless postgres?

    properties = [ create(:property), create(:property, description: nil) ]

    get properties_path(order: { description: { asc: :nulls_last } }, limit: 100, format: 'json')
    assert_equal properties.map(&:id).sort, JSON(response.body).map { |x| x['id'] }

    get properties_path(order: { description: { asc: :nulls_first } }, limit: 100, format: 'json')
    assert_equal properties.map(&:id).sort.reverse, JSON(response.body).map { |x| x['id'] }
  end

  test 'ordering via nulls_first/last' do
    skip "NULLS FIRST/LAST ordering is only implemented for Postgres by arel-extensions" unless postgres?

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

  test 'group_by only accepts columns of the model' do
    create(:photo, format: 'jpg')
    injection = 'id HAVING (SELECT COUNT(*) FROM accounts) >= 0'

    get '/photos/calculate', params: { select: { count: '*' }, group_by: injection }
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "group_by"', response.body

    get '/photos', params: { limit: 10, group_by: injection }, as: :json
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "group_by"', response.body

    get '/photos/calculate', params: { select: { count: '*' }, group_by: 'nonexistent' }
    assert_response :bad_request

    get '/photos/calculate', params: { select: { count: '*' }, group_by: { 'format' => 'x' } }
    assert_response :bad_request
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
      %{SELECT "properties".* FROM "properties" WHERE "properties"."id" IN (#{bind(1)}, #{bind(2)})},
      %{SELECT "cameras".* FROM "cameras" WHERE "cameras"."id" IN (#{bind(1)}, #{bind(2)})}
    ) do
      assert_no_sql(%{SELECT "properties".* FROM "properties" WHERE "properties"."id" = #{bind(1)} LIMIT #{bind(2)}}) do
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
