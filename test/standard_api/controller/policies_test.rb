require 'standard_api/test_helper'

class ControllerPoliciesTest < ActionDispatch::IntegrationTest

  # Build a throwaway controller with a nested Policy. It gets its own base
  # controller so it never shows up in ApplicationController.descendants (and
  # so in #models or schema.json). Subclasses are tracked weakly, so the
  # controllers are kept in @policy_controllers to stop them being collected
  # before load! finds them.
  def policy_controller(model, policy = Class.new(StandardAPI::Policy))
    @policy_base ||= Class.new(ActionController::Base) do
      include StandardAPI::Controller
    end

    controller = Class.new(@policy_base)
    controller.define_singleton_method(:model) { model }
    controller.const_set(:Policy, policy)
    (@policy_controllers ||= []) << controller
    controller
  end

  def unpolicied_model
    Class.new(ActiveRecord::Base) do
      self.table_name = 'accounts'
      def self.name = 'Unpolicied'
    end
  end

  teardown do
    @policy_controllers&.each do |c|
      c.send(:remove_const, :Policy) if c.const_defined?(:Policy, false)
    end
  end

  test "a nested Policy is registered under the model's prefix on the base controller" do
    assert_equal CamerasController::Policy, ApplicationController.standard_api_policies['camera']
    assert_equal CamerasController::Policy, PropertiesController.standard_api_policies['camera']
  end

  test "GET index orders by what the Policy makes orderable" do
    documents = [create(:document), create(:document)]

    get documents_path, params: { limit: 10, order: { id: :desc } }, as: :json
    assert_response :ok
    assert_equal documents.map(&:id).sort.reverse, JSON.parse(response.body).map { |d| d['id'] }

    get documents_path, params: { limit: 10, order: :file }, as: :json
    assert_response :bad_request
  end

  test "a Policy's helpers stay out of the controller" do
    assert_not ApplicationController.private_method_defined?(:resolve)
    assert_not ApplicationController.ancestors.include?(CamerasController::Policy)
  end

  test "one instance serves a model for the length of a controller" do
    controller = CamerasController.new
    assert_instance_of CamerasController::Policy, controller.send(:model_policy, Camera)
    assert_same controller.send(:model_policy, Camera), controller.send(:model_policy, Camera)
    assert_nil controller.send(:model_policy, unpolicied_model)
    assert_not_same controller.send(:model_policy, Camera), CamerasController.new.send(:model_policy, Camera)
  end

  test 'a model with no Policy raises when described or rendered' do
    model = unpolicied_model

    error = assert_raises(StandardAPI::MissingPolicy) { CamerasController.new.record_policy(model).attributes }
    assert_match(/Unpolicied has no Policy/, error.message)
    assert_equal model, error.model

    assert_raises(StandardAPI::MissingPolicy) { CamerasController.new.record_policy(model.new).attributes }
  end

  test 'a model with no controller declares its Policy by name' do
    assert_equal AccountPolicy, ApplicationController.new.send(:model_policy, Account).class
    assert_equal Account.attribute_names, CamerasController.new.record_policy(Account).attributes.map { |s| s[:name] }
  end

  test 'a constant with the right name that is not a Policy is ignored' do
    model = Class.new(ActiveRecord::Base) do
      self.table_name = 'accounts'
      def self.name = 'String'
    end
    Object.const_set(:StringPolicy, Class.new)

    assert_nil ApplicationController.new.send(:model_policy, model)
  ensure
    Object.send(:remove_const, :StringPolicy)
  end

  test "a model with no Policy doesn't raise when only what it hides is asked for" do
    assert_not ApplicationController.new.record_policy(unpolicied_model.new).hidden?(:name)
  end

  test "a model with no Policy includes nothing" do
    policy = ApplicationController.new.record_policy(unpolicied_model.new)
    assert_not policy.include?(:name)
    assert_equal [], policy.includes({ 'name' => {} })
  end

  test 'an STI subclass uses the Policy of its base class' do
    assert_equal DocumentPolicy, DocumentsController.new.send(:model_policy, Pdf).class
  end

  test 'StandardAPI::Controller includes Policies' do
    base = Class.new(ActionController::Base) { include StandardAPI::Controller }

    assert base.include?(StandardAPI::Policies)
    assert_equal({}, base.standard_api_policies)
  end

  test 'including Policies again keeps what load! registered' do
    controller = policy_controller(Attachment)
    StandardAPI::Policies.load!
    @policy_base.include(StandardAPI::Policies)

    assert_equal({ 'attachment' => controller::Policy }, @policy_base.standard_api_policies)
  end

  test "a nested Policy on a controller without a model is skipped" do
    policy_controller(nil)
    StandardAPI::Policies.load!

    assert_empty @policy_base.standard_api_policies
  end

  test "two nested Policies of one model raise" do
    policy_controller(Attachment)
    policy_controller(Attachment)

    error = assert_raises(StandardAPI::InvalidConfiguration) { StandardAPI::Policies.load! }
    assert_match(/both describe attachment/, error.message)
  end

  test "a nested Policy that isn't a StandardAPI::Policy raises" do
    policy_controller(Attachment, Module.new)

    error = assert_raises(StandardAPI::InvalidConfiguration) { StandardAPI::Policies.load! }
    assert_match(/must be a subclass of StandardAPI::Policy/, error.message)
  end

  test "load! can be repeated" do
    controller = policy_controller(Attachment)
    StandardAPI::Policies.load!
    StandardAPI::Policies.load!

    assert_equal({ 'attachment' => controller::Policy }, @policy_base.standard_api_policies)
  end

end
