module StandardAPI
  module TestCase
    module DestroyTests
      extend ActiveSupport::Testing::Declarative

      test '#destroy.json' do
        m = create_model

        assert_difference("#{model.name}.count", -1) do
          delete resource_path(:destroy, id: m.id, format: :json)
          assert_response :no_content
          assert_equal '', response.body
        end
      end

      test '#destroy.json mask_for' do
        m = create_model

        # This is just to instance @controller
        get resource_path(:show, id: m.id, format: 'json')

        # If #mask_for isn't defined by StandardAPI we don't know how to
        # test other's implementation of #mask_for. Return and don't test.
        return if @controller.method(:mask_for).owner != StandardAPI

        @controller.define_singleton_method(:mask_for) do |table_name|
          { id: m.id + 1 }
        end
        assert_raises(ActiveRecord::RecordNotFound) do
          delete resource_path(:destroy, id: m.id, format: :json)
        end
      end

      test '#destroy.json with array of ids' do
        m1 = create_model
        m2 = create_model
        m3 = create_model

        assert_difference("#{model.name}.count", -3) do
          delete resource_path(:destroy, id: [m1.id, m2.id, m3.id], format: :json)
          assert_response :no_content
          assert_equal '', response.body
        end
      end

      test '#destroy.json with array of comma separated ids' do
        m1 = create_model
        m2 = create_model
        m3 = create_model

        assert_difference("#{model.name}.count", -3) do
          delete resource_path(:destroy, id: "#{m1.id},#{m2.id},#{m3.id}", format: :json)
          assert_response :no_content
          assert_equal '', response.body
        end
      end
    end
  end
end
