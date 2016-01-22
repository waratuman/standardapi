module StandardAPI
  module TestCase
    module ShowTests
      extend ActiveSupport::Testing::Declarative

      test '#show.json' do
        m = create_model

        get :show, params: {id: m.id}, format: :json
        assert_response :ok
        assert_equal m, assigns(singular_name)
        assert JSON.parse(response.body).is_a?(Hash)
      end

      test '#show.json params[:include]' do
        m = create_model
        get :show, params: {id: m.id, include: includes}, format: :json

        json = JSON.parse(response.body)
        includes.each do |included|
          assert json.key?(included.to_s), "#{included.inspect} not included in response"

          association = assigns(singular_name).class.reflect_on_association(included)
          next if !association

          if ['belongs_to', 'has_one'].include?(association.macro.to_s)
            view_attributes(assigns(singular_name).send(included)) do |key, value|
              assert_equal json[included.to_s][key.to_s], value
            end
          else
            m = assigns(singular_name).send(included).first.try(:reload)
            
            m_json = if m && m.has_attribute?(:id)
              json[included.to_s].find { |x| x['id'] == normalize_to_json(m, :id, m.id) }
            elsif m
              json[included.to_s].find { |x| x.keys.all? { |key| x[key] == normalize_to_json(m, key, m[key]) } }
            else
              nil
            end

            view_attributes(m).each do |key, value|
              message = "Model / Attribute: #{m.class.name}##{key}"
              assert_equal m_json[key.to_s], normalize_to_json(m, key, value)
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
          get :show, params: {id: m.id}, format: :json
        end
        @controller.current_mask.delete(plural_name)
      end

    end
  end
end
