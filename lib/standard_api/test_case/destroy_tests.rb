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
        m = create_model
        @controller.current_mask[plural_name] = { id: m.id + 1 }
        assert_raises(ActiveRecord::RecordNotFound) do
          delete :destroy, id: m.id, format: 'json'
        end
        @controller.current_mask.delete(plural_name)
      end

      test 'route to #destroy.json' do
        assert_routing({ method: :delete, path: "/#{plural_name}/1" }, path_with_action('destroy', id: '1'))
        assert_recognizes(path_with_action('destroy', id: '1'), { method: :delete, path: "/#{plural_name}/1" })
      end

    end
  end
end
