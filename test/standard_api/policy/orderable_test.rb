require 'standard_api/test_helper'

class PolicyOrderableTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  def orderable(policy, model = Camera)
    policy.new(CamerasController.new, model).orderable
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

end
