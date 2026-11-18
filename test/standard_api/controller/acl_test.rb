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
    assert_equal [:nested_document_attributes], DocumentsController::ACL.instance_methods(false).sort
    assert_equal DocumentsController::ACL, PropertiesController.instance_method(:nested_document_attributes).owner
  end

  test "a nested ACL does not override the controller's includes and orders" do
    assert_equal StandardAPI::Controller, DocumentsController.instance_method(:orders).owner
    assert_equal StandardAPI::Controller, DocumentsController.instance_method(:includes).owner
  end

  test "GET index orders by what the Policy makes orderable" do
    documents = [create(:document), create(:document)]

    get documents_path, params: { limit: 10, order: { id: :desc } }, as: :json
    assert_response :ok
    assert_equal documents.map(&:id).sort.reverse, JSON.parse(response.body).map { |d| d['id'] }

    get documents_path, params: { limit: 10, order: :file }, as: :json
    assert_response :bad_request
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
      def attributes(record = nil)
        [ :id ]
      end
    end
    StandardAPI::AccessControlList.load!

    assert_not_includes @acl_base.ancestors, controller::ACL
  end

  test "an ACL constant in a controller that doesn't use StandardAPI is skipped" do
    controller = Class.new(ActionController::Base)
    controller.const_set(:ACL, Module.new { def attributes(record = nil) = [ :id ] })
    (@acl_controllers ||= []) << controller

    assert_nothing_raised { StandardAPI::AccessControlList.load! }
    assert_not_includes ApplicationController.ancestors, controller::ACL
  end

  test "two nested ACLs of one model defining the same method raise" do
    acl_controller(Attachment) do
      def nested
        [ :document ]
      end
    end
    acl_controller(Attachment) do
      def nested
        [ :record ]
      end
    end

    error = assert_raises(StandardAPI::InvalidConfiguration) { StandardAPI::AccessControlList.load! }
    assert_match(/both define nested_attachment_attributes/, error.message)
  end

  test "load! can be repeated" do
    acl_controller(Attachment) do
      def nested
        [ :document ]
      end
    end
    StandardAPI::AccessControlList.load!
    StandardAPI::AccessControlList.load!

    assert_equal [:nested_attachment_attributes], @acl_controller::ACL.instance_methods(false)
    assert_equal 1, @acl_base.ancestors.count(@acl_controller::ACL)
    assert_equal [:document], @acl_base.new.nested_attachment_attributes
  end

end
