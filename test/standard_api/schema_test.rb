require 'standard_api/test_helper'

class SchemaTest < ActionDispatch::IntegrationTest

  KEYS = %i(name type enum default primary_key null array comment
    auto_populated read_only required validations)

  # Register +schema+ for Camera in place of CamerasController::Schema
  def with_schema(schema)
    ApplicationController.stubs(:standard_api_schemas).returns('camera' => schema)
    yield
  end

  # Most declarations are simplest to check against the whole model
  def schema_class(&block)
    Class.new(StandardAPI::ImplicitSchema, &block)
  end

  def explicit_schema_class(&block)
    Class.new(StandardAPI::Schema, &block)
  end

  def definitions(schema, record = Camera, controller: CamerasController.new)
    with_schema(schema) { controller.schemas_for(record) }
  end

  def names(...) = definitions(...).map { |d| d[:name] }

  def definition(schema, name, ...)
    definitions(schema, ...).find { |d| d[:name] == name }
  end

  test 'only declared attributes are used, in attribute order' do
    schema = explicit_schema_class do
      attributes :make, :id
      attribute :thumbnail_url, :string
    end

    assert_equal ['id', 'make', 'thumbnail_url'], names(schema)
  end

  test 'declaring nothing uses nothing' do
    assert_empty names(explicit_schema_class)
  end

  test 'a declared attribute keeps what the model says about it' do
    make = definition(explicit_schema_class { attributes :make }, 'make')

    assert_equal 'string', make[:type]
    assert_equal false, make[:null]
    assert_equal KEYS, make.keys
  end

  test 'a new column stays hidden until it is declared' do
    camera = create(:camera)
    schema = explicit_schema_class { attributes :id, :make }

    with_schema(schema) do
      get camera_path(camera, format: 'json')
      assert_response :ok
      assert_equal ['id', 'make'], JSON(response.body).keys.sort

      get json_schema_cameras_path(format: 'json')
      assert_equal ['id', 'make'], JSON(response.body)['properties'].keys.sort
    end
  end

  test 'a select the Schema does not declare is not rendered' do
    camera = create(:camera)
    selected = Camera.select('cameras.*, 1 AS rank').find(camera.id)

    assert_equal ['id'], names(explicit_schema_class { attributes :id }, selected)
    assert_includes names(schema_class, selected), 'rank'
  end

  test 'an undeclared attribute is excluded, so its validation error is withheld' do
    property = create(:property)
    ApplicationController.stubs(:standard_api_schemas).returns('property' => explicit_schema_class { attributes :id })

    excluded = PropertiesController.new.send(:excludes, property)
    assert_equal true, excluded[:name]
    assert_not excluded.key?(:id)

    with_schema(explicit_schema_class { attributes :id }) do
      post '/cameras', params: { camera: { make: nil } }, as: :json
    end
    assert_response :bad_request
    assert_not JSON(response.body)['errors'].key?('make')
  end

  test 'attributes declared at runtime count as declared' do
    schema = explicit_schema_class do
      attributes :id
      dynamic_attributes { |builder, _| builder.attributes(:make) }
    end

    assert_equal ['id', 'make'], names(schema)
  end

  test 'attributes raises for an attribute the model lacks' do
    error = assert_raises(ArgumentError) { definitions(explicit_schema_class { attributes :mkae }) }
    assert_match(/Camera has no attribute mkae/, error.message)
  end

  test 'add is attribute, in either mode and at runtime' do
    assert_equal ['thumbnail_url'], names(explicit_schema_class { add :thumbnail_url, :string })
    assert_equal Camera.attribute_names + ['thumbnail_url'], names(schema_class { add :thumbnail_url, :string })
    assert_equal ['make'], names(explicit_schema_class { add :make })
    assert_equal ['thumbnail_url'], names(explicit_schema_class { dynamic_attributes { |builder, _| builder.add(:thumbnail_url, :string) } })
  end

  test 'ImplicitSchema starts from every attribute, and a subclass can opt back out' do
    assert_equal Camera.attribute_names, names(schema_class)
    assert_equal Camera.attribute_names, names(Class.new(schema_class))
    assert_equal ['id'], names(Class.new(schema_class) { implicit_attributes false; attributes :id })
  end

  test 'implicit_attributes opts in without inheriting ImplicitSchema' do
    assert_equal Camera.attribute_names, names(explicit_schema_class { implicit_attributes })
    assert_not explicit_schema_class.schema_implicit
  end

  test 'implicit_attributes on StandardAPI::Schema sets the default for an application' do
    StandardAPI::Schema.implicit_attributes
    assert_equal Camera.attribute_names, names(explicit_schema_class)
    assert_equal ['id'], names(explicit_schema_class { implicit_attributes false; attributes :id })
  ensure
    StandardAPI::Schema.implicit_attributes false
  end

  test 'attribute changes a definition in place' do
    schema = schema_class { attribute :make, comment: 'Who made it', read_only: true }

    assert_equal Camera.attribute_names, names(schema)
    assert_equal 'Who made it', definition(schema, 'make')[:comment]
    assert_equal true, definition(schema, 'make')[:read_only]
    assert_equal 'string', definition(schema, 'make')[:type]
  end

  test 'attribute changes a type' do
    assert_equal 'text', definition(schema_class { attribute :make, :text }, 'make')[:type]
  end

  test 'attribute with a type adds a definition with every key, read only' do
    schema = schema_class { attribute :thumbnail_url, :string, comment: 'A thumbnail' }

    assert_equal Camera.attribute_names + ['thumbnail_url'], names(schema)
    added = definition(schema, 'thumbnail_url')
    assert_equal KEYS, added.keys
    assert_equal({
      name: 'thumbnail_url', type: 'string', enum: nil, default: nil,
      primary_key: false, null: true, array: false, comment: 'A thumbnail',
      auto_populated: false, read_only: true, required: false, validations: []
    }, added)
  end

  test 'attribute without a type raises for an attribute the model lacks' do
    error = assert_raises(ArgumentError) { definitions(schema_class { attribute :mkae, comment: 'Typo' }) }
    assert_match(/Camera has no attribute mkae/, error.message)
  end

  test 'attribute raises for an unknown option' do
    error = assert_raises(ArgumentError) { definitions(schema_class { attribute :make, commnet: 'Typo' }) }
    assert_match(/unknown options for attribute make: commnet/, error.message)
  end

  test "attribute doesn't add a real attribute the query didn't select" do
    camera = create(:camera)
    schema = schema_class do
      attribute :make, :string, comment: 'Who made it'
      attribute :thumbnail_url, :string
    end

    assert_equal ['id', 'thumbnail_url'], names(schema, Camera.select(:id).find(camera.id))
  end

  test "declarations don't change the shared default definitions" do
    default_schema = [{ name: 'make', type: 'string', comment: nil }.freeze].freeze
    builder = StandardAPI::Schema::Builder.new.attribute(:make, comment: 'Who made it').remove(:retired)

    assert_equal [{ name: 'make', type: 'string', comment: 'Who made it' }], builder.apply(default_schema, Camera)
  end

  test 'remove drops definitions' do
    assert_equal Camera.attribute_names - ['make', 'retired'], names(schema_class { remove :make, :retired })
  end

  test 'the last declaration of an attribute wins' do
    assert_includes names(schema_class { remove :make; attribute :make, comment: 'Back' }), 'make'
    assert_not_includes names(schema_class { attribute :make, comment: 'Gone'; remove :make }), 'make'
  end

  test 'a subclass inherits declarations without changing its parent' do
    parent = schema_class { attribute :thumbnail_url, :string }
    child = Class.new(parent) { attribute :preview_url, :string }

    assert_includes names(child), 'thumbnail_url'
    assert_includes names(child), 'preview_url'
    assert_not_includes names(parent), 'preview_url'
  end

  test 'an override can call super' do
    schema = schema_class do
      attribute :make, comment: 'Who made it'
      def schemas(default_schema, record)
        super.map { |d| d[:name] == 'make' ? d.merge(comment: "#{d[:comment]}!") : d }
      end
    end

    assert_equal 'Who made it!', definition(schema, 'make')[:comment]
  end

  test 'dynamic_attributes runs on the instance, once per value of by' do
    runs = []
    schema = schema_class do
      controller_methods :default_limit

      define_method(:seen) { |key| runs << key }
      dynamic_attributes by: ->(record) { record&.make } do |builder, make|
        seen(make)
        builder.attribute("#{make || 'none'}_limit", :integer, comment: default_limit.to_s)
      end
    end
    sony, other_sony, leica = create(:camera, make: 'Sony'), create(:camera, make: 'Sony'), create(:camera, make: 'Leica')
    controller = CamerasController.new
    controller.stubs(:default_limit).returns(7)

    assert_includes names(schema, sony, controller: controller), 'Sony_limit'
    assert_not_includes names(schema, leica, controller: controller), 'Sony_limit'
    assert_includes names(schema, leica, controller: controller), 'Leica_limit'
    names(schema, other_sony, controller: controller)
    assert_includes names(schema, controller: controller), 'none_limit'
    assert_equal ['Sony', 'Leica', nil], runs
    assert_equal '7', definition(schema, 'Sony_limit', sony, controller: controller)[:comment]
  end

  test 'by may name a method, and without by the block runs once' do
    runs = 0
    schema = schema_class do
      dynamic_attributes(by: :make_of) { |builder, make| builder.attribute("#{make}_url", :string) }
      dynamic_attributes { |builder, key| runs += 1; builder.attribute('fixed_url', :string, comment: key.inspect) }

      private def make_of(record) = record&.make
    end
    sony, leica = create(:camera, make: 'Sony'), create(:camera, make: 'Leica')
    controller = CamerasController.new

    assert_includes names(schema, sony, controller: controller), 'Sony_url'
    assert_includes names(schema, leica, controller: controller), 'Leica_url'
    assert_equal 'nil', definition(schema, 'fixed_url', sony, controller: controller)[:comment]
  end

  test 'controller_methods reach private controller methods' do
    schema = schema_class { controller_methods :secret_of_controller; public :secret_of_controller }
    controller = CamerasController.new
    controller.define_singleton_method(:secret_of_controller) { :secret }
    controller.singleton_class.send(:private, :secret_of_controller)

    assert_equal :secret, schema.new(controller, Camera).secret_of_controller
  end

  test 'params comes from the controller' do
    controller = CamerasController.new
    controller.stubs(:params).returns(ActionController::Parameters.new(a: 1))
    assert_equal 1, CamerasController::Schema.new(controller, Camera).send(:params)[:a]
  end

  test 'if and unless take a Proc, with or without the record, or a method' do
    schema = schema_class do
      attribute :make, if: ->(record) { record&.retired? }
      attribute :hidden, unless: ->(record) { record&.retired? }
      attribute :retired, if: -> { false }
      attribute :photo_id, if: :never?
      attribute :id, if: :retired_record?

      private def never? = false
      private def retired_record?(record) = record&.retired?
    end
    retired, active = create(:camera, retired: true), create(:camera, retired: false)
    controller = CamerasController.new

    assert_equal ['id', 'make'], names(schema, retired, controller: controller) & %w(id make hidden retired photo_id)
    assert_equal ['hidden'], names(schema, active, controller: controller) & %w(id make hidden retired photo_id)
  end

  test 'a condition is decided for each record, not cached with the definitions' do
    calls = []
    schema = schema_class do
      dynamic_attributes(by: ->(_) { :same }) do |builder, _|
        builder.attribute :make, if: ->(record) { calls << record&.id; record&.retired? }
      end
    end
    retired, active = create(:camera, retired: true), create(:camera, retired: false)
    controller = CamerasController.new

    assert_includes names(schema, retired, controller: controller), 'make'
    assert_not_includes names(schema, active, controller: controller), 'make'
    # and once each, though both the definitions and excludes ask
    with_schema(schema) do
      controller.send(:model_hidden_attributes, retired)
      controller.send(:model_hidden_attributes, active)
    end
    assert_equal [retired.id, active.id], calls
  end

  test 'a condition is given nil for a model, so json_schema.json follows it' do
    seen = []
    schema = schema_class { attribute :make, if: ->(record) { seen << record; false } }

    assert_not_includes names(schema), 'make'
    assert_equal [nil], seen

    with_schema(schema) do
      get json_schema_cameras_path(format: 'json')
      assert_response :ok
      assert_not JSON(response.body)['properties'].key?('make')
    end
  end

  test 'what a Schema hides is excluded' do
    property = create(:property)
    schema = schema_class do
      attribute :name, if: -> { false }
      remove :description
    end
    ApplicationController.stubs(:standard_api_schemas).returns('property' => schema)

    excluded = PropertiesController.new.send(:excludes, property)
    assert_equal true, excluded[:name]
    assert_equal true, excluded[:description]
    assert_not excluded.key?(:size)
  end

  test "a hidden attribute's validation error is withheld" do
    schema = schema_class { attribute :make, if: -> { false } }

    with_schema(schema) do
      post "/cameras", params: { camera: { make: nil } }, as: :json
    end
    assert_response :bad_request
    json = JSON(response.body)
    assert_not json.key?('make')
    assert_not json['errors'].key?('make')
  end

  test 'varies_by_requester? is false only for unconditional declarations' do
    assert_not schema_class.varies_by_requester?
    assert_not schema_class { attribute :make, comment: 'Who made it'; remove :retired }.varies_by_requester?
    assert_not Class.new(schema_class { attribute :make, comment: 'Who made it' }).varies_by_requester?

    assert schema_class { attribute :make, if: -> { true } }.varies_by_requester?
    assert schema_class { attribute :make, unless: -> { true } }.varies_by_requester?
    assert schema_class { dynamic_attributes { |_, _| } }.varies_by_requester?
    assert schema_class { def schemas(default_schema, record) = default_schema }.varies_by_requester?
    assert Class.new(schema_class { attribute :make, if: -> { true } }).varies_by_requester?
  end

  test 'a Schema that could vary by requester counts as an exclude rule' do
    ApplicationController.stubs(:standard_api_schemas).returns('property' => schema_class { attribute :name, comment: 'Its name' })
    assert_not AccountsController.new.send(:excludes?, Property)

    ApplicationController.stubs(:standard_api_schemas).returns('property' => schema_class { attribute :name, if: -> { true } })
    assert AccountsController.new.send(:excludes?, Property)
  end

  def property_hiding_name_by_header
    schema_class do
      controller_methods :request
      attribute :name, unless: -> { request.headers['X-Hide-Name'] == '1' }
    end
  end

  test 'a hidden attribute is not served from a fragment cached for another requester' do
    ApplicationController.stubs(:standard_api_schemas).returns('property' => property_hiding_name_by_header)
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name']

    get account_path(account, include: :property, format: :json), headers: { 'X-Hide-Name' => '1' }
    assert_not JSON(response.body)['property'].key?('name'),
      'hidden attribute leaked from a fragment cached for a different requester'
  end

  test 'a requester an attribute is hidden from does not poison the fragment cache' do
    ApplicationController.stubs(:standard_api_schemas).returns('property' => property_hiding_name_by_header)
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json), headers: { 'X-Hide-Name' => '1' }
    assert_not JSON(response.body)['property'].key?('name')

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name'],
      'permitted attribute was hidden by a fragment cached for a restricted requester'
  end

  test 'unconditional declarations keep fragment caching' do
    ApplicationController.stubs(:standard_api_schemas).returns('property' => schema_class { attribute :name, comment: 'Its name' })
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name']

    property.update_column(:name, 'Changed')
    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name'], 'expected a cache hit'
  end

end
