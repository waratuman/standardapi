require 'standard_api/test_helper'

class PolicyAttributesForTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

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

end
