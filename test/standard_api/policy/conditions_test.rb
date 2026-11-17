require 'standard_api/test_helper'

class PolicyConditionsTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

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

end
