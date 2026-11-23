require 'standard_api/test_helper'

class PolicyWritableTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  def writable(policy, record = nil, model: Camera)
    policy.new(CamerasController.new, model).permitted_attributes(record)
  end

  test 'writable is what attributes and writable declare writable' do
    policy = empty_policy_class do
      attributes :make, :hidden, writable: true
      attribute :retired
      writable :password
    end

    assert_equal %w[make hidden password], writable(policy)
  end

  test 'writable takes what the column does' do
    Camera.stubs(:type_for_attribute).returns(ActiveRecord::Type::Json.new)
    # A json column takes an object, or null (which the controller keeps)
    assert_equal [{ 'make' => {} }], writable(empty_policy_class { attribute :make, writable: true })
  end

  test 'POST create and PATCH update set a json column to an object or null' do
    with_camera_policy(proc { attribute :metadata, writable: true }) do
      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: { 'iso' => 100, 'lens' => ['35mm'] } } }, as: :json
      assert_response :created
      camera = Camera.last
      assert_equal({ 'iso' => 100, 'lens' => ['35mm'] }, camera.metadata)

      patch camera_path(camera, format: 'json'), params: { camera: { metadata: nil } }, as: :json
      assert_response :ok
      assert_nil camera.reload.metadata

      post cameras_path(format: 'json'), params: { camera: { make: 'Canon', metadata: nil } }, as: :json
      assert_response :created
      assert_nil Camera.last.metadata
    end
  end

  test "POST create and PATCH update drop a json column's scalar or array, as strong parameters drop what isn't permitted" do
    with_camera_policy(proc { attribute :metadata, writable: true }) do
      camera = create(:camera, metadata: { 'iso' => 100 })

      [1, 'auto', true, [1, 2], [{ 'iso' => 200 }]].each do |value|
        patch camera_path(camera, format: 'json'), params: { camera: { make: 'Canon', metadata: value } }, as: :json
        assert_response :ok
        assert_equal({ 'iso' => 100 }, camera.reload.metadata, "#{value.inspect} was saved")
      end

      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: [1, 2] } }, as: :json
      assert_response :created
      assert_nil Camera.last.metadata
    end
  end

  test 'a json column takes an array with permit:' do
    with_camera_policy(proc { attribute :metadata, writable: { permit: [] } }) do
      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: [1, 'a'] } }, as: :json
      assert_response :created
      assert_equal [1, 'a'], Camera.last.metadata
    end

    with_camera_policy(proc { attribute :metadata, writable: { permit: [:iso] } }) do
      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: [{ iso: 100 }, { iso: 200 }] } }, as: :json
      assert_response :created
      assert_equal [{ 'iso' => 100 }, { 'iso' => 200 }], Camera.last.metadata
    end
  end

  test 'writable takes an array for an array column' do
    skip 'array columns are a Postgres-only feature' if !postgres?

    policy = empty_policy_class { attribute :aliases, writable: true }
    assert_equal [{ 'aliases' => [] }], writable(policy, model: Property)
  end

  test 'writable takes what a strong parameters Array or permit gives instead' do
    policy = empty_policy_class do
      attribute :make, writable: [:name, { filter: {} }]
      writable :specs, permit: {}
    end

    assert_equal [{ 'make' => [:name, { filter: {} }] }, { 'specs' => {} }], writable(policy)
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

  test 'Policy::Record#writable is empty without a Policy' do
    with_model_policy(Camera, nil) do
      assert_equal [], ApplicationController.new.record_policy(Camera).writable
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
