require 'standard_api/test_helper'

class ControllerSchemasTest < ActionDispatch::IntegrationTest

  # Build a throwaway controller with a nested Schema, as
  # ControllerACLTest#acl_controller does with an ACL.
  def schema_controller(model, schema = Class.new(StandardAPI::Schema))
    @schema_base ||= Class.new(ActionController::Base) do
      include StandardAPI::Controller
      include StandardAPI::AccessControlList
      include StandardAPI::Schemas
    end

    controller = Class.new(@schema_base)
    controller.define_singleton_method(:model) { model }
    controller.const_set(:Schema, schema)
    (@schema_controllers ||= []) << controller
    controller
  end

  def unschemaed_model
    Class.new(ActiveRecord::Base) do
      self.table_name = 'accounts'
      def self.name = 'Unschemaed'
    end
  end

  teardown do
    @schema_controllers&.each do |c|
      c.send(:remove_const, :Schema) if c.const_defined?(:Schema, false)
    end
  end

  test "a nested Schema is registered under the model's prefix on the base controller" do
    assert_equal CamerasController::Schema, ApplicationController.standard_api_schemas['camera']
    assert_equal CamerasController::Schema, PropertiesController.standard_api_schemas['camera']
    assert_not ApplicationController.method_defined?(:camera_schemas)
  end

  test "a Schema's helpers stay out of the controller" do
    assert_not ApplicationController.private_method_defined?(:resolve)
    assert_not ApplicationController.ancestors.include?(CamerasController::Schema)
  end

  test "one instance serves a model for the length of a controller" do
    controller = CamerasController.new
    assert_instance_of CamerasController::Schema, controller.send(:model_schema, Camera)
    assert_same controller.send(:model_schema, Camera), controller.send(:model_schema, Camera)
    assert_nil controller.send(:model_schema, unschemaed_model)
    assert_not_same controller.send(:model_schema, Camera), CamerasController.new.send(:model_schema, Camera)
  end

  test 'a model with no Schema raises when described or rendered' do
    model = unschemaed_model

    error = assert_raises(StandardAPI::MissingSchema) { CamerasController.new.schemas_for(model) }
    assert_match(/Unschemaed has no Schema/, error.message)
    assert_equal model, error.model

    assert_raises(StandardAPI::MissingSchema) { CamerasController.new.schemas_for(model.new) }
  end

  test 'a model with no controller declares its Schema by name' do
    assert_equal AccountSchema, ApplicationController.new.send(:model_schema, Account).class
    assert_equal Account.attribute_names, CamerasController.new.schemas_for(Account).map { |s| s[:name] }
  end

  test 'a constant with the right name that is not a Schema is ignored' do
    model = Class.new(ActiveRecord::Base) do
      self.table_name = 'accounts'
      def self.name = 'String'
    end
    Object.const_set(:StringSchema, Class.new)

    assert_nil ApplicationController.new.send(:model_schema, model)
  ensure
    Object.send(:remove_const, :StringSchema)
  end

  test "a model with no Schema doesn't raise when only its excludes are asked for" do
    assert_nil ApplicationController.new.send(:model_hidden_attributes, unschemaed_model.new)
  end

  test 'an STI subclass uses the Schema of its base class' do
    assert_equal DocumentSchema, DocumentsController.new.send(:model_schema, Pdf).class
  end

  test "a base controller without Schemas doesn't register a Schema" do
    base = Class.new(ActionController::Base) do
      include StandardAPI::Controller
      include StandardAPI::AccessControlList
    end
    controller = Class.new(base)
    controller.define_singleton_method(:model) { Attachment }
    controller.const_set(:Schema, Class.new(StandardAPI::Schema))
    (@schema_controllers ||= []) << controller

    StandardAPI::Schemas.load!
    assert_not base.respond_to?(:standard_api_schemas)
  end

  test "a nested Schema on a controller without a model is skipped" do
    schema_controller(nil)
    StandardAPI::Schemas.load!

    assert_empty @schema_base.standard_api_schemas
  end

  test "two nested Schemas of one model raise" do
    schema_controller(Attachment)
    schema_controller(Attachment)

    error = assert_raises(StandardAPI::InvalidConfiguration) { StandardAPI::Schemas.load! }
    assert_match(/both describe attachment/, error.message)
  end

  test "a nested Schema that isn't a StandardAPI::Schema raises" do
    schema_controller(Attachment, Module.new)

    error = assert_raises(StandardAPI::InvalidConfiguration) { StandardAPI::Schemas.load! }
    assert_match(/must be a subclass of StandardAPI::Schema/, error.message)
  end

  test "load! can be repeated" do
    controller = schema_controller(Attachment)
    StandardAPI::Schemas.load!
    StandardAPI::Schemas.load!

    assert_equal({ 'attachment' => controller::Schema }, @schema_base.standard_api_schemas)
  end

end
