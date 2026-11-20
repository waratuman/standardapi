require 'standard_api/test_helper'

class PolicyRecordTest < ActiveSupport::TestCase

  def controller
    @controller ||= PropertiesController.new
  end

  def with_account_policy(policy)
    policies = ApplicationController.standard_api_policies.merge('account' => policy)
    ApplicationController.stubs(:standard_api_policies).returns(policies)
    yield
  ensure
    ApplicationController.unstub(:standard_api_policies)
  end

  test 'attributes are what the Policy declares, or the one given in its place' do
    account = create(:account)
    through = Class.new(StandardAPI::Policy) { attributes :id, :name }

    assert_includes controller.record_policy(account).attributes.map { |d| d[:name] }, 'email'
    policy = controller.record_policy(account, through)
    assert_equal %w[id name], policy.attributes.map { |d| d[:name] }.sort
    assert policy.attribute?(:name)
    assert_not policy.attribute?(:email)
  end

  test 'include? is false for an association or method a Policy hides or does not declare' do
    account = create(:account)
    through = Class.new(StandardAPI::Policy) { associations :photos }

    with_account_policy(Class.new(AccountPolicy) { remove :property }) do
      policy = controller.record_policy(account)
      assert_not policy.include?(:property)
      assert policy.include?(:photos)
      assert_not policy.include?(:not_an_association)
      assert_not controller.record_policy(account, through).include?(:subject)
    end
  end

  test 'association_policy gives the Policy an association renders its records with' do
    through = Class.new(StandardAPI::Policy) { attributes :id }
    with_account_policy(Class.new(AccountPolicy) { association :photos, policy: through }) do
      policy = controller.record_policy(create(:account))
      assert_equal through, policy.association_policy(:photos)
      assert_nil policy.association_policy(:property)
    end
  end

  test 'includes gives the includes it renders, with what to include of them and their Policy' do
    through = Class.new(StandardAPI::Policy) { attributes :id }
    with_account_policy(Class.new(AccountPolicy) { remove :property; association :photos, policy: through; association :specs }) do
      includes = { 'photos' => { 'camera' => {} }, 'property' => {}, 'specs' => {}, 'limit' => 1 }
      assert_equal [['photos', { 'camera' => {} }, through], ['specs', {}, nil]],
        controller.record_policy(create(:account)).includes(includes)
    end
  end

  test "orderable is the model's, whatever the record" do
    with_account_policy(Class.new(AccountPolicy) { attribute :name, orderable: true, if: -> { record&.persisted? } }) do
      assert_equal %w[id property], controller.record_policy(Account).orderable
      assert_equal %w[id property], controller.record_policy(create(:account)).orderable
    end
  end

  test 'orderable is [] without a Policy' do
    controller.stubs(:model_policy).returns(nil)
    assert_equal [], controller.record_policy(Account).orderable
  end

  test "filterable is the model's, whatever the record" do
    with_account_policy(Class.new(AccountPolicy) { attribute :name, filterable: true, if: -> { record&.persisted? } }) do
      assert_equal({ 'id' => :all }, controller.record_policy(Account).filterable)
      assert_equal({ 'id' => :all }, controller.record_policy(create(:account)).filterable)
    end
  end

  test 'filterable is {} without a Policy' do
    controller.stubs(:model_policy).returns(nil)
    assert_equal({}, controller.record_policy(Account).filterable)
  end

  test 'hidden? is false for a name that is neither an attribute nor an association' do
    assert_not controller.record_policy(create(:account)).hidden?(:not_an_attribute)
  end

  test 'hidden? is true for an attribute the Policy adds and hides' do
    account = create(:account)
    policy = Class.new(AccountPolicy) do
      attribute :nickname, :string, if: -> { false }
      attribute :initials, :string, value: -> { 'AB' }, unless: -> { record&.persisted? }
      attribute :shown, :string, if: -> { true }
    end

    with_account_policy(policy) do
      assert controller.record_policy(account).hidden?(:nickname)
      assert controller.record_policy(account).hidden?(:initials)
      assert_not controller.record_policy(Account).hidden?(:initials)
      assert_not controller.record_policy(account).hidden?(:shown)
    end
  end

  test 'errors leave out those on what it hides' do
    account = build(:account)
    account.errors.add(:email, 'is taken by someone@example.com')
    account.errors.add(:name, 'is blank')
    account.errors.add(:base, 'is wrong')

    with_account_policy(Class.new(AccountPolicy) { remove :email }) do
      assert_equal %w[base name], controller.record_policy(account).errors.keys.map(&:to_s).sort
    end
  end

end
