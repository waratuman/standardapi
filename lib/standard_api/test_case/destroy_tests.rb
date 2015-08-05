module StandardAPI
  module TestCase
    module DestroyTests
      extend ActiveSupport::Testing::Declarative

      test '#destroy.json' do
        m = create_model

        assert_difference("#{model.name}.count", -1) do
          delete :destroy, id: m.id, format: 'json'
          assert_response :no_content
          assert_equal '', response.body
        end
      end

      test '#destroy.json mask' do
        # If #current_mask isn't defined by StandardAPI we don't know how to
        # test other's implementation of #current_mask. Return and don't test.
        return if @controller.method(:current_mask).owner != StandardAPI

        m = create_model
        @controller.current_mask[plural_name] = { id: m.id + 1 }
        assert_raises(ActiveRecord::RecordNotFound) do
          delete :destroy, id: m.id, format: 'json'
        end
        @controller.current_mask.delete(plural_name)
      end

    end
  end
end
