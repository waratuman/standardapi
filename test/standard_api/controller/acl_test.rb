require 'standard_api/test_helper'

class ControllerACLTest < ActionDispatch::IntegrationTest

  # Build a throwaway controller with a nested ACL module. It gets its own base
  # controller so it never shows up in ApplicationController.descendants (and
  # so in #models or schema.json). Subclasses are tracked weakly, so the
  # controllers are kept in @acl_controllers to stop them being collected
  # before load! finds them; teardown removes their ACL so later calls to
  # load! skip them.
  def acl_controller(model, &acl)
    @acl_base ||= Class.new(ActionController::Base) do
      include StandardAPI::Controller
      include StandardAPI::AccessControlList
    end

    @acl_controller = Class.new(@acl_base)
    @acl_controller.define_singleton_method(:model) { model }
    @acl_controller.const_set(:ACL, Module.new(&acl))
    (@acl_controllers ||= []) << @acl_controller
    @acl_controller
  end

  teardown do
    @acl_controllers&.each { |c| c.send(:remove_const, :ACL) }
  end

  test "a nested ACL is renamed under the model's prefix and included into the base controller" do
    assert_includes ApplicationController.ancestors, DocumentsController::ACL
    assert_equal [:document_attributes, :document_orders], DocumentsController::ACL.instance_methods(false).sort
    assert_equal DocumentsController::ACL, PropertiesController.instance_method(:document_attributes).owner
  end

  test "a nested ACL does not override the controller's includes and orders" do
    assert_equal StandardAPI::Controller, DocumentsController.instance_method(:orders).owner
    assert_equal StandardAPI::Controller, DocumentsController.instance_method(:includes).owner
  end

  test "a nested ACL keeps its record argument" do
    movie = create(:document, type: 'movie')
    controller = PropertiesController.new

    assert_equal [:file, :type], controller.model_attributes(Document)
    assert_equal [:file, :type, :rating], controller.model_attributes(Document, movie)
  end

  test "GET index applies orders from a nested ACL" do
    documents = [create(:document), create(:document)]

    get documents_path, params: { limit: 10, order: { id: :desc } }, as: :json
    assert_response :ok
    assert_equal documents.map(&:id).sort.reverse, JSON.parse(response.body).map { |d| d['id'] }

    get documents_path, params: { limit: 10, order: :file }, as: :json
    assert_response :bad_request
  end

  test "includes and orders in a nested ACL do not shadow the controller's" do
    acl_controller(Attachment) do
      def includes
        [ :record ]
      end

      def orders
        [ :id ]
      end
    end
    StandardAPI::AccessControlList.load!

    controller = @acl_base.new
    assert_equal [:record], controller.attachment_includes
    assert_equal [:id], controller.attachment_orders
    assert_equal StandardAPI::Controller, @acl_controller.instance_method(:includes).owner
  end

  test "nested and filter are renamed to their own names" do
    acl_controller(Attachment) do
      def nested
        [ :record ]
      end

      def filter(record, params, **)
        params
      end
    end
    StandardAPI::AccessControlList.load!

    assert @acl_base.method_defined?(:nested_attachment_attributes)
    assert @acl_base.method_defined?(:filter_attachment_params)
  end

  test "a nested ACL on a controller without a model is skipped" do
    controller = acl_controller(nil) do
      def orders
        [ :id ]
      end
    end
    StandardAPI::AccessControlList.load!

    assert_not_includes @acl_base.ancestors, controller::ACL
  end

  test "an ACL constant in a controller that doesn't use StandardAPI is skipped" do
    controller = Class.new(ActionController::Base)
    controller.const_set(:ACL, Module.new { def orders = [ :id ] })
    (@acl_controllers ||= []) << controller

    assert_nothing_raised { StandardAPI::AccessControlList.load! }
    assert_not_includes ApplicationController.ancestors, controller::ACL
  end

  test "load! can be repeated" do
    acl_controller(Attachment) do
      def orders
        [ :id ]
      end
    end
    StandardAPI::AccessControlList.load!
    StandardAPI::AccessControlList.load!

    assert_equal [:attachment_orders], @acl_controller::ACL.instance_methods(false)
    assert_equal 1, @acl_base.ancestors.count(@acl_controller::ACL)
    assert_equal [:id], @acl_base.new.attachment_orders
  end

end
