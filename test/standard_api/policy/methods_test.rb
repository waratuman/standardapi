require 'standard_api/test_helper'

class PolicyMethodsTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

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

end
