require 'standard_api/test_helper'

class PolicyTest < ActionDispatch::IntegrationTest

  KEYS = %i(name type enum default primary_key null array comment
    auto_populated read_only required validations)

  # Register +policy+ for Camera in place of CamerasController::Policy
  def with_policy(policy)
    ApplicationController.stubs(:standard_api_policies).returns('camera' => policy)
    yield
  end

  # A Policy declaring every attribute of +model+, then what +block+ does
  def policy_class(model = Camera, &block)
    names = model.attribute_names
    Class.new(StandardAPI::Policy) do
      attributes(*names)
      class_eval(&block) if block
    end
  end

  def empty_policy_class(&block)
    Class.new(StandardAPI::Policy, &block)
  end

  def definitions(policy, record = Camera, controller: CamerasController.new)
    with_policy(policy) { controller.record_policy(record).attributes }
  end

  def names(...) = definitions(...).map { |d| d[:name] }

  def definition(policy, name, ...)
    definitions(policy, ...).find { |d| d[:name] == name }
  end

  def camera_json(path)
    get "/cameras/#{path}", params: { format: 'json' }
    assert_response :ok
    JSON(response.body)
  end

  test 'schema.json lists only what the Policy declares' do
    policy = empty_policy_class do
      attributes :id, :make
      attribute :hidden, if: -> { false }
      attribute :thumbnail_url, :string, comment: 'Small'
    end

    with_policy(policy) do
      attributes = camera_json('schema')['attributes']
      assert_equal ['id', 'make', 'thumbnail_url'], attributes.keys
      assert_equal 'string', attributes.dig('thumbnail_url', 'type')
      assert_equal 'Small', attributes.dig('thumbnail_url', 'comment')
      assert_equal true, attributes.dig('thumbnail_url', 'readonly')
    end
  end

  test 'schema.json uses a type the Policy declares for a column' do
    policy = empty_policy_class { attribute :make, :integer }

    with_policy(policy) do
      assert_equal 'integer', camera_json('schema').dig('attributes', 'make', 'type')
    end
  end

  test 'schema.json at the root lists only what the Policy declares' do
    with_policy(empty_policy_class { attributes :id }) do
      get '/schema', params: { format: 'json' }
      assert_response :ok
      assert_equal ['id'], JSON(response.body).dig('models', 'Camera', 'attributes').keys
    end
  end

  test 'schema.json and schema/write.json follow a declared read_only' do
    policy = empty_policy_class do
      attribute :photo_id, read_only: true
      attribute :id, read_only: false
      attributes :make
    end

    with_policy(policy) do
      attributes = camera_json('schema')['attributes']
      assert_equal true, attributes.dig('photo_id', 'readonly')
      assert_equal false, attributes.dig('id', 'readonly')

      # CameraACL permits photo_id and make, but not id
      properties = camera_json('schema/write').dig('properties', 'camera', 'properties')
      assert_equal true, properties.dig('photo_id', 'readOnly')
      assert_nil properties.dig('make', 'readOnly')
    end
  end

  test 'schema/read.json, write.json and query.json are not found for a controller without a model' do
    assert_nil SessionsController.model

    %w(read write query).each do |kind|
      get "/sessions/schema/#{kind}.json"
      assert_response :not_found, kind
    end
  end

  test 'only declared attributes are used, in attribute order' do
    policy = empty_policy_class do
      attributes :make, :id
      attribute :thumbnail_url, :string
    end

    assert_equal ['id', 'make', 'thumbnail_url'], names(policy)
  end

  test 'declaring nothing uses nothing' do
    assert_empty names(empty_policy_class)
  end

  test 'a declared attribute keeps what the model says about it' do
    make = definition(empty_policy_class { attributes :make }, 'make')

    assert_equal 'string', make[:type]
    assert_equal false, make[:null]
    assert_equal KEYS, make.keys
  end

  test 'a new column stays hidden until it is declared' do
    camera = create(:camera)
    policy = empty_policy_class { attributes :id, :make }

    with_policy(policy) do
      get camera_path(camera, format: 'json')
      assert_response :ok
      assert_equal ['id', 'make'], JSON(response.body).keys.sort

      get read_schema_cameras_path(format: 'json')
      assert_equal ['errors', 'id', 'make'], JSON(response.body)['properties'].keys.sort
    end
  end

  test 'a select the Policy does not declare is not rendered' do
    camera = create(:camera)
    selected = Camera.select('cameras.*, 1 AS rank').find(camera.id)

    assert_equal ['id'], names(empty_policy_class { attributes :id }, selected)
    assert_equal ['id', 'rank'], names(empty_policy_class { attributes :id; attribute :rank, :integer }, selected)
  end

  test 'attributes declared at runtime count as declared' do
    policy = empty_policy_class do
      attributes :id
      attributes_for(-> { :all }) { attributes :make }
    end

    assert_equal ['id', 'make'], names(policy)
  end

  test 'attributes raises for an attribute the model lacks' do
    error = assert_raises(ArgumentError) { definitions(empty_policy_class { attributes :mkae }) }
    assert_match(/Camera has no attribute mkae/, error.message)
  end

  test 'attribute and remove declare at runtime too' do
    policy = empty_policy_class do
      attributes :id, :make
      attributes_for(-> { :all }) do
        attribute :thumbnail_url, :string
        remove :make
      end
    end

    assert_equal ['id', 'thumbnail_url'], names(policy)
  end

  test 'attribute changes a definition in place' do
    policy = policy_class { attribute :make, comment: 'Who made it', read_only: true }

    assert_equal Camera.attribute_names, names(policy)
    assert_equal 'Who made it', definition(policy, 'make')[:comment]
    assert_equal true, definition(policy, 'make')[:read_only]
    assert_equal 'string', definition(policy, 'make')[:type]
  end

  test 'attribute changes a type' do
    assert_equal 'text', definition(policy_class { attribute :make, :text }, 'make')[:type]
  end

  test 'attribute with a type adds a definition with every key, read only' do
    policy = policy_class { attribute :thumbnail_url, :string, comment: 'A thumbnail' }

    assert_equal Camera.attribute_names + ['thumbnail_url'], names(policy)
    added = definition(policy, 'thumbnail_url')
    assert_equal KEYS, added.keys
    assert_equal({
      name: 'thumbnail_url', type: 'string', enum: nil, default: nil,
      primary_key: false, null: true, array: false, comment: 'A thumbnail',
      auto_populated: false, read_only: true, required: false, validations: []
    }, added)
  end

  test 'attribute without a type raises for an attribute the model lacks' do
    error = assert_raises(ArgumentError) { definitions(policy_class { attribute :mkae, comment: 'Typo' }) }
    assert_match(/Camera has no attribute mkae/, error.message)
  end

  test 'attribute raises for an unknown option' do
    error = assert_raises(ArgumentError) { definitions(policy_class { attribute :make, commnet: 'Typo' }) }
    assert_match(/unknown options for attribute make: commnet/, error.message)
  end

  test "attribute doesn't add a real attribute the query didn't select" do
    camera = create(:camera)
    policy = policy_class do
      attribute :make, :string, comment: 'Who made it'
      attribute :thumbnail_url, :string
    end

    assert_equal ['id', 'thumbnail_url'], names(policy, Camera.select(:id).find(camera.id))
  end

  test "declarations don't change the shared default definitions" do
    defaults = [{ name: 'make', type: 'string', comment: nil }.freeze].freeze
    builder = StandardAPI::Policy::Builder.new.attribute(:make, comment: 'Who made it').remove(:retired)

    assert_equal [{ name: 'make', type: 'string', comment: 'Who made it' }], builder.apply(defaults, Camera)
  end

  test 'remove takes back a declaration' do
    assert_equal Camera.attribute_names - ['make', 'retired'], names(policy_class { remove :make, :retired })
  end

  test 'remove takes back what a parent declares, without changing it' do
    parent = empty_policy_class { attributes :id, :make }
    child = Class.new(parent) { remove :make }

    assert_equal ['id'], names(child)
    assert_equal ['id', 'make'], names(parent)
  end

  test 'the last declaration of an attribute wins' do
    assert_includes names(policy_class { remove :make; attribute :make, comment: 'Back' }), 'make'
    assert_not_includes names(policy_class { attribute :make, comment: 'Gone'; remove :make }), 'make'
  end

  test 'a subclass inherits declarations without changing its parent' do
    parent = policy_class { attribute :thumbnail_url, :string }
    child = Class.new(parent) { attribute :preview_url, :string }

    assert_includes names(child), 'thumbnail_url'
    assert_includes names(child), 'preview_url'
    assert_not_includes names(parent), 'preview_url'
  end

  test 'attributes_for runs on the instance, once per key' do
    runs = []
    policy = policy_class do
      define_method(:seen) { |key| runs << key }
      attributes_for -> { record&.make } do |make|
        seen(make)
        attribute "#{make || 'none'}_limit", :integer, comment: default_limit.to_s
      end
    end
    sony, other_sony, leica = create(:camera, make: 'Sony'), create(:camera, make: 'Sony'), create(:camera, make: 'Leica')
    controller = CamerasController.new
    controller.stubs(:default_limit).returns(7)

    assert_includes names(policy, sony, controller: controller), 'Sony_limit'
    assert_not_includes names(policy, leica, controller: controller), 'Sony_limit'
    assert_includes names(policy, leica, controller: controller), 'Leica_limit'
    names(policy, other_sony, controller: controller)
    assert_includes names(policy, controller: controller), 'none_limit'
    assert_equal ['Sony', 'Leica', nil], runs
    assert_equal '7', definition(policy, 'Sony_limit', sony, controller: controller)[:comment]
  end

  test 'a key may name a method, and a Policy may have several' do
    policy = policy_class do
      attributes_for(:make_of) { |make| attribute "#{make}_url", :string }
      attributes_for(-> { record&.retired? }) { |retired| attribute "retired_#{retired}", :string }

      private def make_of = record&.make
    end
    sony, leica = create(:camera, make: 'Sony', retired: true), create(:camera, make: 'Leica', retired: false)
    controller = CamerasController.new

    assert_empty ['Sony_url', 'retired_true'] - names(policy, sony, controller: controller)
    assert_empty ['Leica_url', 'retired_false'] - names(policy, leica, controller: controller)
  end

  test 'attributes_for needs a key and a block' do
    assert_raises(ArgumentError) { empty_policy_class { attributes_for { } } }
    error = assert_raises(ArgumentError) { empty_policy_class { attributes_for :make_of } }
    assert_match(/needs a block/, error.message)
  end

  test 'attributes can only be declared while the Policy is built' do
    policy = empty_policy_class.new(CamerasController.new, Camera)

    error = assert_raises(ArgumentError) { policy.send(:attribute, :make) }
    assert_match(/class body or an attributes_for block/, error.message)
  end

  test 'a failed attributes_for block leaves nothing half declared' do
    calls = 0
    policy = empty_policy_class do
      attributes_for(-> { :all }) do
        calls += 1
        raise 'failed' if calls == 1
        attribute :make
      end
    end
    controller = CamerasController.new

    assert_raises(RuntimeError) { names(policy, controller: controller) }
    assert_equal ['make'], names(policy, controller: controller)
  end

  test 'an unknown method reaches private controller methods' do
    controller = CamerasController.new
    controller.define_singleton_method(:secret_of_controller) { |arg, key:, &block| [arg, key, block.call] }
    controller.singleton_class.send(:private, :secret_of_controller)
    policy = policy_class.new(controller, Camera)

    assert policy.respond_to?(:secret_of_controller, true)
    assert_equal [1, 2, 3], policy.send(:secret_of_controller, 1, key: 2) { 3 }
  end

  test "a Policy's own methods win over the controller's" do
    policy = policy_class { private def params = :from_policy }

    assert_equal :from_policy, policy.new(CamerasController.new, Camera).send(:params)
  end

  test 'a method neither has raises' do
    policy = policy_class.new(CamerasController.new, Camera)

    assert_not policy.respond_to?(:not_a_real_method, true)
    assert_raises(NoMethodError) { policy.send(:not_a_real_method) }
  end

  test 'params comes from the controller' do
    controller = CamerasController.new
    controller.stubs(:params).returns(ActionController::Parameters.new(a: 1))
    assert_equal 1, CamerasController::Policy.new(controller, Camera).send(:params)[:a]
  end

  test 'if and unless take a Proc or a method that reads record' do
    policy = policy_class do
      attribute :make, if: -> { record&.retired? }
      attribute :hidden, unless: -> { record&.retired? }
      attribute :retired, if: -> { false }
      attribute :photo_id, if: :never?
      attribute :id, if: :retired_record?

      private def never? = false
      private def retired_record? = record&.retired?
    end
    retired, active = create(:camera, retired: true), create(:camera, retired: false)
    controller = CamerasController.new

    assert_equal ['id', 'make'], names(policy, retired, controller: controller) & %w(id make hidden retired photo_id)
    assert_equal ['hidden'], names(policy, active, controller: controller) & %w(id make hidden retired photo_id)
  end

  test 'a condition passes record to a controller method that needs it' do
    controller = CamerasController.new
    controller.define_singleton_method(:hide_camera?) { |camera| camera&.retired? }
    controller.singleton_class.send(:private, :hide_camera?)
    policy = policy_class { attribute :make, unless: -> { hide_camera?(record) } }

    assert_includes names(policy, create(:camera, retired: false), controller: controller), 'make'
    assert_not_includes names(policy, create(:camera, retired: true), controller: controller), 'make'
  end

  test 'a named controller method is called without the record' do
    controller = CamerasController.new
    controller.define_singleton_method(:hide_camera?) { |camera| camera&.retired? }
    policy = policy_class { attribute :make, unless: :hide_camera? }

    assert_raises(ArgumentError) { names(policy, create(:camera), controller: controller) }
  end

  test 'a condition that takes an argument raises' do
    policy = policy_class { attribute :make, if: ->(camera) { camera } }

    assert_raises(ArgumentError) { names(policy) }
  end

  test 'record raises in an attributes_for block' do
    policy = policy_class { attributes_for(-> { :all }) { record } }

    error = assert_raises(ArgumentError) { names(policy) }
    assert_match(/use the key it is given/, error.message)
  end

  test 'record is only set while a condition runs' do
    policy = policy_class { attribute :make, if: -> { record&.retired? } }
    camera = create(:camera, retired: true)
    instance = policy.new(CamerasController.new, Camera)

    assert_equal camera, instance.send(:resolve, -> { record }, camera)
    assert_nil instance.send(:record)
    assert_raises(RuntimeError) { instance.send(:resolve, -> { raise 'failed' }, camera) }
    assert_nil instance.send(:record)
  end

  test 'a condition is decided for each record, not cached with the definitions' do
    calls = []
    policy = policy_class do
      attributes_for(-> { :same }) do
        attribute :make, if: -> { calls << record&.id; record&.retired? }
      end
    end
    retired, active = create(:camera, retired: true), create(:camera, retired: false)
    controller = CamerasController.new

    assert_includes names(policy, retired, controller: controller), 'make'
    assert_not_includes names(policy, active, controller: controller), 'make'
    # and once each, though both the definitions and excludes ask
    with_policy(policy) do
      controller.send(:model_policy, Camera).hidden_attributes(retired)
      controller.send(:model_policy, Camera).hidden_attributes(active)
    end
    assert_equal [retired.id, active.id], calls
  end

  test 'record is nil for a model, so schema/read.json follows it' do
    seen = []
    policy = policy_class { attribute :make, if: -> { seen << record; false } }

    assert_not_includes names(policy), 'make'
    assert_equal [nil], seen

    with_policy(policy) do
      get read_schema_cameras_path(format: 'json')
      assert_response :ok
      assert_not JSON(response.body)['properties'].key?('make')
    end
  end

  test 'what a Policy hides is excluded' do
    property = create(:property)
    policy = policy_class(Property) do
      attribute :name, if: -> { false }
      remove :description
    end
    ApplicationController.stubs(:standard_api_policies).returns('property' => policy)

    policy = PropertiesController.new.record_policy(property)
    assert policy.hidden?(:name)
    assert policy.hidden?(:description)
    assert_not policy.hidden?(:size)
  end

  test "a hidden attribute's validation error is withheld" do
    undeclared = empty_policy_class { attributes :id }
    condition = policy_class { attribute :make, if: -> { false } }

    [undeclared, condition].each do |policy|
      with_policy(policy) do
        post "/cameras", params: { camera: { make: nil } }, as: :json
      end
      assert_response :bad_request
      json = JSON(response.body)
      assert_not json.key?('make')
      assert_not json['errors'].key?('make')
    end
  end

  test 'varies_by_requester? is false only for unconditional declarations' do
    assert_not policy_class.varies_by_requester?
    assert_not policy_class { attribute :make, comment: 'Who made it'; remove :retired }.varies_by_requester?
    assert_not Class.new(policy_class { attribute :make, comment: 'Who made it' }).varies_by_requester?

    assert policy_class { attribute :make, if: -> { true } }.varies_by_requester?
    assert policy_class { attribute :make, unless: -> { true } }.varies_by_requester?
    assert policy_class { attributes_for(-> { :all }) { } }.varies_by_requester?
    assert Class.new(policy_class { attribute :make, if: -> { true } }).varies_by_requester?
  end

  test 'policy_varies? is whether the model\'s Policy could vary by requester' do
    ApplicationController.stubs(:standard_api_policies).returns('property' => policy_class(Property) { attribute :name, comment: 'Its name' })
    assert_not AccountsController.new.send(:policy_varies?, Property)

    ApplicationController.stubs(:standard_api_policies).returns('property' => policy_class(Property) { attribute :name, if: -> { true } })
    assert AccountsController.new.send(:policy_varies?, Property)
  end

  test 'policy_varies? with includes is whether any Policy they reach could vary' do
    varying = policy_class(Photo) { attribute :format, if: -> { true } }
    ApplicationController.stubs(:standard_api_policies).returns('account' => AccountPolicy, 'photo' => varying)
    controller = AccountsController.new

    assert_not controller.send(:policy_varies?, Account)
    assert controller.send(:policy_varies?, Account, { 'photos' => {} })
    assert_not controller.send(:policy_varies?, Account, { 'limit' => 1 })
    # A polymorphic association could be any model
    assert controller.send(:policy_varies?, Account, { 'subject' => {} })
  end

  def property_hiding_name_by_header
    policy_class(Property) do
      attribute :name, unless: -> { request.headers['X-Hide-Name'] == '1' }
    end
  end

  test 'a hidden attribute is not served from a fragment cached for another requester' do
    ApplicationController.stubs(:standard_api_policies).returns('property' => property_hiding_name_by_header)
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name']

    get account_path(account, include: :property, format: :json), headers: { 'X-Hide-Name' => '1' }
    assert_not JSON(response.body)['property'].key?('name'),
      'hidden attribute leaked from a fragment cached for a different requester'
  end

  test 'a requester an attribute is hidden from does not poison the fragment cache' do
    ApplicationController.stubs(:standard_api_policies).returns('property' => property_hiding_name_by_header)
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json), headers: { 'X-Hide-Name' => '1' }
    assert_not JSON(response.body)['property'].key?('name')

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name'],
      'permitted attribute was hidden by a fragment cached for a restricted requester'
  end

  test 'unconditional declarations keep fragment caching' do
    ApplicationController.stubs(:standard_api_policies).returns('property' => policy_class(Property) { attribute :name, comment: 'Its name' })
    property = create(:property, name: 'The Shard')
    account = create(:account, property: property, property_cached_at: 1.day.ago)

    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name']

    property.update_column(:name, 'Changed')
    get account_path(account, include: :property, format: :json)
    assert_equal 'The Shard', JSON(response.body)['property']['name'], 'expected a cache hit'
  end

end
