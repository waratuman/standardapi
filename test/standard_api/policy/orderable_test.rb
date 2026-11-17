require 'standard_api/test_helper'

class PolicyOrderableTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  def orderable(policy, model = Camera)
    policy.new(CamerasController.new, model).permitted_orders
  end

  test 'orderable is what attributes and associations declare orderable' do
    policy = empty_policy_class do
      attributes :id, :make, orderable: true
      attribute :created_at
      association :photo, orderable: true
      association :specs
    end

    assert_equal %w[id make photo], orderable(policy)
  end

  test 'orderable: false takes back an inherited one, as does remove' do
    parent = empty_policy_class { attributes :id, :make, :created_at, orderable: true }

    assert_equal %w[id created_at], orderable(Class.new(parent) { attribute :make, orderable: false })
    assert_equal %w[id make], orderable(Class.new(parent) { remove :created_at })
  end

  test 'orderable leaves out what a condition hides from the model' do
    policy = empty_policy_class do
      attribute :id, orderable: true
      attribute :make, orderable: true, if: -> { record&.persisted? }
      association :photo, orderable: true, unless: -> { true }
    end

    assert_equal %w[id], orderable(policy)
  end

  test 'orderable includes what attributes_for declares for the model' do
    policy = empty_policy_class do
      attributes_for(-> { :key }) { |key| attribute :make, orderable: key == :key }
    end

    assert_equal %w[make], orderable(policy)
  end

  test 'GET index orders by what the Policy makes orderable' do
    cameras = [create(:camera, make: 'b'), create(:camera, make: 'a')]

    with_camera_policy(proc { attribute :make, orderable: true }) do
      get cameras_path(format: 'json'), params: { order: { make: :asc }, limit: 10 }
      assert_response :ok
      assert_equal cameras.map(&:id).reverse, JSON(response.body).map { |c| c['id'] }
    end

    get cameras_path(format: 'json'), params: { order: { make: :asc }, limit: 10 }
    assert_response :bad_request
  end

  def required_orders(policy, model = Camera)
    policy.new(CamerasController.new, model).permitted_required_orders
  end

  test 'required_orders are listed in order, and orderable without being declared' do
    policy = empty_policy_class do
      attribute :make, orderable: true
      required_orders :created_at, :id
    end

    assert_equal %w[created_at id], required_orders(policy)
    assert_equal %w[make created_at id], orderable(policy)
  end

  test 'remove and orderable: false take back an inherited required order' do
    parent = empty_policy_class { required_orders :created_at, :id }

    assert_equal %w[id], required_orders(Class.new(parent) { remove :created_at })
    assert_equal %w[created_at], required_orders(Class.new(parent) { attribute :id, orderable: false })
    assert_equal %w[created_at], orderable(Class.new(parent) { attribute :id, orderable: false })
  end

  test 'required_orders leaves out what a condition hides from the model' do
    policy = empty_policy_class do
      attribute :created_at, if: -> { record&.persisted? }
      required_orders :created_at, :id
    end

    assert_equal %w[id], required_orders(policy)
  end

  test 'required_orders can be declared in attributes_for' do
    policy = empty_policy_class do
      attributes_for(-> { :key }) { |key| required_orders :id if key == :key }
    end

    assert_equal %w[id], required_orders(policy)
  end

  test 'Policy::Record#required_orders is empty without a Policy' do
    with_model_policy(Camera, nil) do
      assert_equal [], ApplicationController.new.record_policy(Camera).required_orders
    end
  end

  test 'GET index orders by required_orders after what the request orders by' do
    with_camera_policy(proc { attribute :make, orderable: true; required_orders :id }) do
      get cameras_path(format: 'json'), params: { order: { make: :asc }, limit: 10 }
      assert_response :ok
      assert_equal [{ make: 'asc' }, 'id'], controller.send(:orders)

      # Not twice when the request orders by it
      get cameras_path(format: 'json'), params: { order: [{ make: :asc }, { id: :desc }], limit: 10 }
      assert_equal [{ make: 'asc' }, { id: 'desc' }], controller.send(:orders)
      get cameras_path(format: 'json'), params: { order: 'id', limit: 10 }
      assert_equal 'id', controller.send(:orders)
    end
  end

  test 'GET index orders by default_orders then required_orders without an order' do
    with_camera_policy(proc { attribute :make, orderable: true; required_orders :id }) do
      get cameras_path(format: 'json'), params: { limit: 10 }
      assert_response :ok
      assert_equal ['id'], controller.send(:orders)
      assert_nil controller.params[:order]

      CamerasController.any_instance.stubs(:default_orders).returns({ make: :desc })
      get cameras_path(format: 'json'), params: { limit: 10 }
      assert_equal [{ make: :desc }, 'id'], controller.send(:orders)
    ensure
      CamerasController.any_instance.unstub(:default_orders)
    end
  end

end
