module StandardAPI
  module TestCase
    module CreateTests
      extend ActiveSupport::Testing::Declarative

      test '#create.json' do
        attrs = attributes_for(singular_name, :nested).select{ |k,v| !model.readonly_attributes.include?(k.to_s) }
        mask.each { |k, v| attrs[k] = v }
        create_webmocks(attrs)

        file_upload = attrs.any? { |k, v| v.is_a?(Rack::Test::UploadedFile) }
        as = file_upload ? nil : :json

        assert_difference("#{model.name}.count") do
          post resource_path(:create), params: { singular_name => attrs }, as: as

          break if as != :json

          assert_response :created
          m = @controller.instance_variable_get("@#{singular_name}")

          json = JSON.parse(response.body)
          assert json.is_a?(Hash)

          create_attributes(m.reload).select { |x| attrs.keys.map(&:to_s).include?(x) }.each do |key, value|
            message = "Model / Attribute: #{m.class.name}##{key}"
            if value.is_a?(BigDecimal)
              assert_equal_or_nil normalize_to_json(m, key, attrs[key.to_sym]).to_s.to_f, json[key.to_s].to_s.to_f, message
            else
              assert_equal_or_nil normalize_to_json(m, key, attrs[key.to_sym]), json[key.to_s], message
            end
          end
        end
      end

      test '#create.json with nested attributes' do
        attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        mask.each { |k, v| attrs[k] = v }
        create_webmocks(attrs)

        file_upload = attrs.any? { |k, v| v.is_a?(Rack::Test::UploadedFile) }
        as = file_upload ? nil : :json

        assert_difference("#{model.name}.count") do
          post resource_path(:create), params: {singular_name => attrs}, as: as

          break if as != :json

          assert_response :created
          m = @controller.instance_variable_get("@#{singular_name}")
          assert m

          json = JSON.parse(response.body)
          assert json.is_a?(Hash)
          m.reload
          create_attributes(m).select { |x| attrs.keys.map(&:to_s).include?(x) }.each do |key, value|
            message = "Model / Attribute: #{m.class.name}##{key}"
            assert_equal_or_nil normalize_attribute(m, key, attrs[key.to_sym]), normalize_attribute(m, key, value), message
          end
        end
      end

      test '#create.json with invalid attributes' do
        trait = FactoryBot.factories[singular_name].definition.defined_traits.any? { |x| x.name.to_s == 'invalid' }

        if !trait
          Rails.logger.try(:warn, "No invalid trait for #{model.name}. Skipping invalid tests")
          warn("No invalid trait for #{model.name}. Skipping invalid tests")
          return
        end

        attrs = attributes_for(singular_name, :invalid).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        file_upload = attrs.any? { |k, v| v.is_a?(Rack::Test::UploadedFile) }
        as = file_upload ? nil : :json

        assert_difference("#{model.name}.count", 0) do
          post resource_path(:create), params: { singular_name => attrs }, as: as
          assert_response :bad_request
          json = JSON.parse(response.body)
          assert json.is_a?(Hash)
          assert json['errors']
        end
      end

      test '#create.html' do
        return unless supports_format(:html, :create)

        attrs = attributes_for(singular_name, :nested).select do |k,v|
          !model.readonly_attributes.include?(k.to_s)
        end

        mask.each { |k, v| attrs[k] = v }
        create_webmocks(attrs)

        assert_difference("#{model.name}.count") do
          post resource_path(:create), params: { singular_name => attrs }, as: :html
          assert_response :redirect
        end
      end

      test '#create.html with invalid attributes renders edit action' do
        return unless supports_format(:html, :create)

        trait = FactoryBot.factories[singular_name].definition.defined_traits.any? { |x| x.name.to_s == 'invalid' }

        if !trait
          Rails.logger.try(:warn, "No invalid trait for #{model.name}. Skipping invalid tests")
          warn("No invalid trait for #{model.name}. Skipping invalid tests")
          return
        end

        attrs = attributes_for(singular_name, :invalid).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        assert_difference("#{model.name}.count", 0) do
          post resource_path(:create), params: { singular_name => attrs }, as: :html
          assert_response :bad_request
        end
      end

      test '#create.json params[:include]' do
        travel_to Time.now do
          attrs = attributes_for(singular_name, :nested).select{ |k,v| !model.readonly_attributes.include?(k.to_s) }
          create_webmocks(attrs)

          file_upload = attrs.any? { |k, v| v.is_a?(Rack::Test::UploadedFile) }
          as = file_upload ? nil : :json

          assert_difference("#{model.name}.count") do
            post resource_path(:create), params: { singular_name => attrs, include: includes }, as: as

            break if as != :json

            assert_response :created
            m = @controller.instance_variable_get("@#{singular_name}")
            assert m

            json = JSON.parse(response.body)
            assert json.is_a?(Hash)
            includes.each do |included|
              assert json.key?(included.to_s), "#{included.inspect} not included in response"

              association = m.class.reflect_on_association(included)
              next if !association

              if ['belongs_to', 'has_one'].include?(association.macro.to_s)
                create_attributes(m.send(included)) do |key, value|
                  assert_equal json[included.to_s][key.to_s], normalize_to_json(m, key, value)
                end
              else
                m2 = m.send(included).first.try(:reload)

                m_json = if m2 && m2.has_attribute?(:id)
                  json[included.to_s].find { |x| x['id'] == normalize_to_json(m2, :id, m2.id) }
                elsif m2
                  json[included.to_s].find { |x| x.keys.all? { |key| x[key] == normalize_to_json(m2, key, m2[key]) } }
                else
                  nil
                end

                create_attributes(m2).each do |key, value|
                  message = "Model / Attribute: #{m2.class.name}##{key}"
                  if m_json[key.to_s].nil?
                    assert_nil normalize_to_json(m2, key, value), message
                  else
                    assert_equal m_json[key.to_s], normalize_to_json(m2, key, value), message
                  end
                end

              end
            end
          end
        end
      end

    end
  end
end
