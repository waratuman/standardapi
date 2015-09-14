module StandardAPI
  module TestCase
    module UpdateTests
      extend ActiveSupport::Testing::Declarative

      test '#update.json' do
        m = create_model
        attrs = attributes_for(singular_name).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        put :update, id: m.id, singular_name => attrs, format: 'json'
        assert_response :ok

        view_attributes(m.reload).select { |x| attrs.keys.map(&:to_s).include?(x) }.each do |key, value|
          message = "Model / Attribute: #{m.class.name}##{key}"
          assert_equal normalize_attribute(m, key, attrs[key.to_sym]), value, message
        end
        assert JSON.parse(@response.body).is_a?(Hash)
      end

      test '#update.json with nested attributes' do
        m = create_model
        attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)
        put :update, id: m.id, singular_name => attrs, format: 'json'
        assert_response :ok

        # (m.attribute_names & attrs.keys.map(&:to_s)).each do |test_key|
        view_attributes(m.reload).select { |x| attrs.keys.map(&:to_s).include?(x) }.each do |key, value|
          message = "Model / Attribute: #{m.class.name}##{key}"
          assert_equal normalize_attribute(m, key, attrs[key.to_sym]), value, message
        end
        assert JSON.parse(@response.body).is_a?(Hash)
      end

      test '#update.json with invalid attributes' do
        m = create_model
        attrs = attributes_for(singular_name, :invalid).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        put :update, id: m.id, singular_name => attrs, format: 'json'
        assert_response :bad_request
        assert JSON.parse(@response.body)['errors']
      end

      test '#update.json params[:include]' do
        travel_to Time.now do
          m = create_model
          attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k) }
          create_webmocks(attrs)

          put :update, id: m.id, include: includes, singular_name => attrs, format: 'json'

          json = JSON.parse(response.body)
          includes.each do |included|
            assert json.key?(included.to_s), "#{included.inspect} not included in response"

            association = assigns(:record).class.reflect_on_association(included)
            next if !association

            if ['belongs_to', 'has_one'].include?(association.macro.to_s)
              view_attributes(assigns(:record).send(included)) do |key, value|
                message = "Model / Attribute: #{assigns(:record).send(included).class.name}##{key}"
                assert_equal json[included.to_s][key.to_s], value, message
              end
            else
              m = assigns(:record).send(included).first.try(:reload)
              view_attributes(m).each do |key, value|
                message = "Model / Attribute: #{m.class.name}##{key}"
                assert_equal normalize_to_json(assigns(:record), key, value), json[included.to_s][0][key.to_s], message
              end
            end
          end
        end
      end

      test '#update.json mask' do
        # If #current_mask isn't defined by StandardAPI we don't know how to
        # test other's implementation of #current_mask. Return and don't test.
        return if @controller.method(:current_mask).owner != StandardAPI

        m = create_model
        @controller.current_mask[plural_name] = { id: m.id + 1 }
        assert_raises(ActiveRecord::RecordNotFound) do
          put :update, id: m.id, format: 'json'
        end
        @controller.current_mask.delete(plural_name)
      end

    end
  end
end
