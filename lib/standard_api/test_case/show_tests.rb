module StandardAPI
  module TestCase
    module ShowTests
      extend ActiveSupport::Testing::Declarative

      test '#show.json' do
        m = create_model

        get :show, id: m.id, format: 'json'
        assert_response :ok
        assert_template :show
        assert_equal m, assigns(singular_name)
        assert JSON.parse(response.body).is_a?(Hash)
      end

      test '#show.json params[:include]' do
        m = create_model
        get :show, id: m.id, include: includes, format: 'json'

        json = JSON.parse(response.body)
        includes.each do |included|
          assert json.key?(included.to_s), "#{included.inspect} not included in response"

          association = assigns(:record).class.reflect_on_association(included)
          next if !association

          if ['belongs_to', 'has_one'].include?(association.macro.to_s)
            view_attributes(assigns(:record).send(included)) do |key, value|
              assert_equal json[included.to_s][key.to_s], value
            end
          else
            m = assigns(:record).send(included).first.try(:reload)
            view_attributes(m).each do |key, value|
              assert_equal normalize_to_json(m, key, value), json[included.to_s][0][key.to_s]
            end
          end
        end
      end

      test '#show.json mask' do
        # If #current_mask isn't defined by StandardAPI we don't know how to
        # test other's implementation of #current_mask. Return and don't test.
        return if @controller.method(:current_mask).owner != StandardAPI

        m = create_model
        @controller.current_mask[plural_name] = { id: m.id + 1 }
        assert_raises(ActiveRecord::RecordNotFound) do
          get :show, id: m.id, format: 'json'
        end
        @controller.current_mask.delete(plural_name)
      end

    end
  end
end
