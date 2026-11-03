require 'standard_api/test_helper'

class ControllerSchemasTest < ActionDispatch::IntegrationTest

  # Build a throwaway controller with a nested Schema module, as
  # ControllerACLTest#acl_controller does with an ACL. Its base controller
  # includes both AccessControlList and Schemas, so the two can be checked
  # against each other.
  def schema_controller(model, &schema)
    @schema_base ||= Class.new(ActionController::Base) do
      include StandardAPI::Controller
      include StandardAPI::AccessControlList
      include StandardAPI::Schemas
    end

    controller = Class.new(@schema_base)
    controller.define_singleton_method(:model) { model }
    controller.const_set(:Schema, Module.new(&schema))
    (@schema_controllers ||= []) << controller
    controller
  end

  teardown do
    @schema_controllers&.each do |c|
      c.send(:remove_const, :Schema) if c.const_defined?(:Schema, false)
      c.send(:remove_const, :ACL) if c.const_defined?(:ACL, false)
    end
  end

  test "a nested Schema is renamed under the model's prefix and included into the base controller" do
    assert_includes ApplicationController.ancestors, CamerasController::Schema
    assert_equal [:camera_schemas], CamerasController::Schema.instance_methods(false)
    assert_equal CamerasController::Schema, PropertiesController.instance_method(:camera_schemas).owner
  end

  test "Schemas.load! includes a Schema and leaves the ACL to AccessControlList.load!" do
    controller = schema_controller(Attachment) do
      def schemas(default_schema) = default_schema.first(1)
    end
    controller.const_set(:ACL, Module.new { def orders = [ :id ] })

    StandardAPI::Schemas.load!
    assert_equal [:a], @schema_base.new.attachment_schemas([:a, :b])
    assert_not @schema_base.method_defined?(:attachment_orders)

    StandardAPI::AccessControlList.load!
    assert_equal [:id], @schema_base.new.attachment_orders
  end

  test "a base controller without Schemas doesn't include a Schema" do
    base = Class.new(ActionController::Base) do
      include StandardAPI::Controller
      include StandardAPI::AccessControlList
    end
    controller = Class.new(base)
    controller.define_singleton_method(:model) { Attachment }
    controller.const_set(:Schema, Module.new { def schemas(default_schema) = default_schema })
    (@schema_controllers ||= []) << controller

    StandardAPI::Schemas.load!
    assert_not_includes base.ancestors, controller::Schema
  end

  test "a nested Schema on a controller without a model is skipped" do
    controller = schema_controller(nil) do
      def schemas(default_schema) = default_schema
    end
    StandardAPI::Schemas.load!

    assert_not_includes @schema_base.ancestors, controller::Schema
  end

  test "two nested Schemas of one model raise" do
    schema_controller(Attachment) do
      def schemas(default_schema) = default_schema
    end
    schema_controller(Attachment) do
      def schemas(default_schema) = default_schema.first(1)
    end

    error = assert_raises(StandardAPI::InvalidConfiguration) { StandardAPI::Schemas.load! }
    assert_match(/both define attachment_schemas/, error.message)
  end

  test "a Schema and an ACL defining the same helper raise" do
    controller = schema_controller(Attachment) do
      def schemas(default_schema) = default_schema
      private def shared_helper = nil
    end
    controller.const_set(:ACL, Module.new { private def shared_helper = nil })

    StandardAPI::Schemas.load!
    error = assert_raises(StandardAPI::InvalidConfiguration) { StandardAPI::AccessControlList.load! }
    assert_match(/both define shared_helper/, error.message)
  end

  test "load! can be repeated" do
    controller = schema_controller(Attachment) do
      def schemas(default_schema) = default_schema.first(1)
    end
    StandardAPI::Schemas.load!
    StandardAPI::Schemas.load!

    assert_equal [:attachment_schemas], controller::Schema.instance_methods(false)
    assert_equal 1, @schema_base.ancestors.count(controller::Schema)
  end

end
