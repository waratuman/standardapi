module StandardAPI
  module TestCase
    module UpdateTests
      extend ActiveSupport::Testing::Declarative

      test '#update.json' do
        m = create_model
        attrs = attributes_for(singular_name).select{ |k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        put resource_path(:update, :id => m.id, :format => 'json'), params: { singular_name => attrs }
        assert_response :ok, "Updating #{m.class.name} with #{attrs.inspect}"

        view_attributes(m.reload).select { |x| attrs.keys.map(&:to_s).include?(x) }.each do |key, value|
          message = "Model / Attribute: #{m.class.name}##{key}"
          if value.is_a?(BigDecimal)
            assert_equal normalize_attribute(m, key, attrs[key.to_sym]).to_s.to_f, value.to_s.to_f, message
          else
            assert_equal normalize_attribute(m, key, attrs[key.to_sym]), value, message
          end
        end
        assert JSON.parse(@response.body).is_a?(Hash)
      end

      test '#update.html redirects to #show.html' do
        m = create_model

        # This is just to instance @controller
        get resource_path(:show, id: m.id, format: :json)

        return if @controller.method(:update).owner != StandardAPI
        
        attrs = attributes_for(singular_name).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        put resource_path(:update, :id => m.id, :format => 'html'), params: { singular_name => attrs }

        assert_redirected_to m
      end

      test '#update.json with nested attributes' do
        m = create_model
        attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        put resource_path(:update, :id => m.id, :format => 'json'), params: { singular_name => attrs }
        assert_response :ok, "Updating #{m.class.name} with #{attrs.inspect}"

        # (m.attribute_names & attrs.keys.map(&:to_s)).each do |test_key|
        view_attributes(m.reload).select { |x| attrs.keys.map(&:to_s).include?(x) }.each do |key, value|
          message = "Model / Attribute: #{m.class.name}##{key}"
          assert_equal normalize_attribute(m, key, attrs[key.to_sym]), value, message
        end
        assert JSON.parse(@response.body).is_a?(Hash)
      end

      test '#update.json with invalid attributes' do
        trait = FactoryGirl.factories[singular_name].definition.defined_traits.any? { |x| x.name.to_s == 'invalid' }

        if !trait
          Rails.logger.try(:warn, "No invalid trait for #{model.name}. Skipping invalid tests")
          warn("No invalid trait for #{model.name}. Skipping invalid tests")
          return
        end

        m = create_model
        attrs = attributes_for(singular_name, :invalid).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        put resource_path(:update, :id => m.id, :format => 'json'), params: { singular_name => attrs }
        assert_response :bad_request, "Updating #{m.class.name} with invalid attributes #{attrs.inspect}"
        assert JSON.parse(@response.body)['errors']
      end

      test '#update.json params[:include]' do
        travel_to Time.now do
          m = create_model
          attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k) }
          create_webmocks(attrs)

          put resource_path(:update, :id => m.id, :format => 'json'), params: { include: includes, singular_name => attrs }
          assert_response :ok, "Updating #{m.class.name} with #{attrs.inspect}"
        
          controller_model = @controller.instance_variable_get("@#{singular_name}")
          json = JSON.parse(response.body)
          includes.each do |included|
            assert json.key?(included.to_s), "#{included.inspect} not included in response"

            association = controller_model.class.reflect_on_association(included)
            next if !association

            if ['belongs_to', 'has_one'].include?(association.macro.to_s)
              view_attributes(controller_model.send(included)) do |key, value|
                message = "Model / Attribute: #{controller_model.send(included).class.name}##{key}"
                assert_equal json[included.to_s][key.to_s], value, message
              end
            else
              m = controller_model.send(included).first.try(:reload)
              m_json = if m && m.has_attribute?(:id)
                json[included.to_s].find { |x| x['id'] == normalize_to_json(m, :id, m.id) }
              elsif m
                json[included.to_s].find { |x| x.keys.all? { |key| x[key] == normalize_to_json(m, key, m[key]) } }
              else
                nil
              end

              view_attributes(m).each do |key, value|
                message = "Model / Attribute: #{m.class.name}##{key}"
                if m_json[key.to_s].nil?
                  assert_nil normalize_to_json(m, key, value), message
                else
                  assert_equal m_json[key.to_s], normalize_to_json(m, key, value), message
                end
              end

            end
          end
        end
      end

      test '#update.json mask' do
        m = create_model

        # This is just to instance @controller
        get resource_path(:index, format: :json), params: { limit: 1 }

        # If #current_mask isn't defined by StandardAPI we don't know how to
        # test other's implementation of #current_mask. Return and don't test.
        return if @controller.method(:current_mask).owner != StandardAPI

        @controller.current_mask[plural_name] = { id: m.id + 1 }
        assert_raises(ActiveRecord::RecordNotFound) do
          put resource_path(:update, :id => m.id, :format => 'json')
        end
        @controller.current_mask.delete(plural_name)
      end

    end
  end
end
