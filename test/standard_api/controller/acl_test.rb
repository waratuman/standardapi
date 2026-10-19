require 'standard_api/test_helper'

class ControllerACLTest < ActionDispatch::IntegrationTest

  # Build a throwaway controller with a nested ACL module. It gets its own base
  # controller, removed in teardown, so it never shows up in
  # ApplicationController.descendants (and so in #models or schema.json). The
  # base is named before it includes AccessControlList, which registers it by
  # name. Subclasses are tracked weakly, so the controller is kept in
  # @acl_controller to stop it being collected before load! finds it.
  def acl_controller(model, &acl)
    if !@acl_base
      @acl_base = self.class.const_set(:BaseController, Class.new(ActionController::Base))
      @acl_base.include StandardAPI::Controller
      @acl_base.include StandardAPI::AccessControlList
    end

    @acl_controller = Class.new(@acl_base)
    @acl_controller.define_singleton_method(:model) { model }
    @acl_controller.const_set(:ACL, Module.new(&acl))
    @acl_controller
  end

  teardown do
    if @acl_base
      StandardAPI::AccessControlList.base_controllers.delete(@acl_base.name)
      self.class.send(:remove_const, :BaseController)
    end
  end

  test "a nested ACL is renamed under the model's prefix and included into the base controller" do
    assert_includes ApplicationController.ancestors, DocumentsController::ACL
    assert_equal [:document_attributes, :document_orders], DocumentsController::ACL.private_instance_methods(false).sort
    assert_empty DocumentsController::ACL.instance_methods(false)
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
    assert_equal [:record], controller.send(:attachment_includes)
    assert_equal [:id], controller.send(:attachment_orders)
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

    assert @acl_base.private_method_defined?(:nested_attachment_attributes)
    assert @acl_base.private_method_defined?(:filter_attachment_params)
  end

  test "helpers in a nested ACL are rejected" do
    acl_controller(Attachment) do
      def attributes(record = nil)
        allowed
      end

      private

      def allowed
        [ :record_id ]
      end
    end

    error = assert_raises(ArgumentError) { StandardAPI::AccessControlList.load! }
    assert_match(/#allowed is not an ACL method/, error.message)
  end

  test "a nested ACL that duplicates one in app/controllers/acl is rejected" do
    acl_controller(Camera) do
      def includes
        [ :photo ]
      end
    end

    error = assert_raises(ArgumentError) { StandardAPI::AccessControlList.load! }
    assert_match(/camera_includes is defined by both CameraACL and/, error.message)
  end

  test "a controller method with the renamed name is rejected" do
    controller = acl_controller(Attachment) do
      def orders
        [ :id ]
      end
    end
    controller.define_method(:attachment_orders) { [ :id ] }

    error = assert_raises(ArgumentError) { StandardAPI::AccessControlList.load! }
    assert_match(/attachment_orders is defined by both #{Regexp.escape(controller.inspect)} and/, error.message)
  end

  test "a nested ACL on a controller without a model is rejected" do
    acl_controller(nil) do
      def orders
        [ :id ]
      end
    end

    error = assert_raises(ArgumentError) { StandardAPI::AccessControlList.load! }
    assert_match(/has no model/, error.message)
  end

  test "load! can be repeated" do
    acl_controller(Attachment) do
      def orders
        [ :id ]
      end
    end
    StandardAPI::AccessControlList.load!
    StandardAPI::AccessControlList.load!

    assert_equal [:attachment_orders], @acl_controller::ACL.private_instance_methods(false)
    assert_equal 1, @acl_base.ancestors.count(@acl_controller::ACL)
    assert_equal [:id], @acl_base.new.send(:attachment_orders)
  end

end
