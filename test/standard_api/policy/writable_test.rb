require 'standard_api/test_helper'

class PolicyWritableTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  # The names Policy#writable_attributes makes writable
  def writable(policy, record = nil, model: Camera)
    writable_attributes(policy, record, model: model).keys
  end

  def writable_attributes(policy, record = nil, model: Camera)
    policy.new(CamerasController.new, model).writable_attributes(record)
  end

  test 'writable is what attributes and writable declare writable' do
    policy = empty_policy_class do
      attributes :make, :hidden, writable: true
      attribute :retired
      writable :password
    end

    assert_equal %w[make hidden password], writable(policy)
  end

  test 'writable takes a scalar for a column, or a name without one' do
    policy = empty_policy_class { attribute :make, writable: true; writable :password }
    assert_equal({ 'make' => { kind: :scalar }, 'password' => { kind: :scalar } }, writable_attributes(policy))
  end

  test 'writable takes any JSON value for a json column' do
    Camera.stubs(:type_for_attribute).returns(ActiveRecord::Type::Json.new)
    assert_equal({ 'make' => { kind: :json } }, writable_attributes(empty_policy_class { attribute :make, writable: true }))
  end

  test 'writable takes an array for an array column' do
    skip 'array columns are a Postgres-only feature' if !postgres?

    policy = empty_policy_class { attribute :aliases, writable: true }
    assert_equal({ 'aliases' => { kind: :array } }, writable_attributes(policy, model: Property))
  end

  test 'writable takes what a strong parameters Array or permit gives instead' do
    policy = empty_policy_class do
      attribute :make, writable: [:name, { filter: {} }]
      writable :specs, permit: {}
      attribute :metadata, writable: [:a]
    end

    assert_equal({
      'make' => { kind: :permit, permit: [:name, { filter: {} }] },
      'specs' => { kind: :permit, permit: {} },
      'metadata' => { kind: :permit, permit: [:a] }
    }, writable_attributes(policy))
  end


  test 'writable on: :create or :update permits it only on one, a model being a create' do
    policy = empty_policy_class do
      attribute :make, writable: true
      attribute :photo_id, writable: { on: :create }
      attribute :hidden, writable: { on: :update }
      writable :retired, on: :update
    end

    assert_equal %w[make photo_id], writable(policy)
    assert_equal %w[make photo_id], writable(policy, Camera.new)
    assert_equal %w[make hidden retired], writable(policy, create(:camera))
  end

  test 'writable: false takes back an inherited one, as does remove' do
    parent = empty_policy_class { attributes :make, :hidden, :retired, writable: true }

    assert_equal %w[hidden retired], writable(Class.new(parent) { attribute :make, writable: false })
    assert_equal %w[make hidden], writable(Class.new(parent) { remove :retired })
  end

  test "writable isn't changed by a condition, which decides what renders" do
    policy = empty_policy_class do
      attribute :make, writable: true, unless: -> { raise 'not run' }
    end

    assert_equal %w[make], writable(policy, Camera.new)
  end

  test 'writable can be declared in attributes_for, per record' do
    policy = empty_policy_class do
      attributes_for(-> { record&.hidden? }) { |hidden| attribute :make, writable: !hidden }
    end

    assert_equal %w[make], writable(policy, create(:camera))
    assert_equal [], writable(policy, create(:camera, hidden: true))
  end

  test 'a standalone writable is not rendered' do
    assert_equal %w[make], names(empty_policy_class { attribute :make; writable :hidden })
  end

  test 'an invalid writable raises when it is declared' do
    assert_raises(ArgumentError) { empty_policy_class { attribute :make, writable: :yes } }
    assert_raises(ArgumentError) { empty_policy_class { attribute :make, writable: { on: :destroy } } }
    assert_raises(ArgumentError) { empty_policy_class { attribute :make, writable: { if: :admin? } } }
    assert_raises(ArgumentError) { empty_policy_class { writable :make, on: :destroy } }
  end

  test 'a writable attribute is not read only, and required on create when NOT NULL' do
    policy = empty_policy_class do
      attributes :make, :photo_id, writable: true
      attribute :hidden
    end

    assert_equal false, definition(policy, 'make')[:read_only]
    assert_equal true, definition(policy, 'make')[:required]
    # photo_id allows NULL
    assert_equal false, definition(policy, 'photo_id')[:required]
    assert_equal true, definition(policy, 'hidden')[:read_only]
    assert_equal false, definition(policy, 'hidden')[:required]
  end

  test 'one writable on: :create is read only and required, on: :update neither' do
    policy = empty_policy_class do
      attribute :make, writable: { on: :create }
      attribute :hidden, writable: { on: :update }
    end

    assert_equal true, definition(policy, 'make')[:read_only]
    assert_equal true, definition(policy, 'make')[:required]
    assert_equal false, definition(policy, 'hidden')[:read_only]
    assert_equal false, definition(policy, 'hidden')[:required]
  end

  test 'Policy::Record#writable_attributes is empty without a Policy' do
    with_model_policy(Camera, nil) do
      assert_equal({}, ApplicationController.new.record_policy(Camera).writable_attributes)
    end
  end

  test 'POST create and PATCH update set what the Policy makes writable on each' do
    with_camera_policy(proc { attribute :photo_id, writable: { on: :create }; attribute :retired, writable: false }) do
      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', photo_id: 1, retired: true } }
      assert_response :created
      camera = Camera.last
      assert_equal [1, false], [camera.photo_id, camera.retired]

      patch camera_path(camera, format: 'json'), params: { camera: { make: 'Canon', photo_id: 2 } }
      assert_response :ok
      assert_equal ['Canon', 1], [camera.reload.make, camera.photo_id]
    end
  end

end
