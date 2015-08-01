module ActionController
  class StandardAPI < ActionController::Base
    module TestCase
      module CreateTests
        extend ActiveSupport::Testing::Declarative

        test '#create.json' do
          attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
          create_webmocks(attrs)

          assert_difference("#{model.name}.count") do
            post :create, singular_name => attrs, :format => 'json'
            assert_response :created
            assert assigns(singular_name)
          
            json = JSON.parse(response.body)
            assert json.is_a?(Hash)
            (model.attribute_names & attrs.keys.map(&:to_s)).each do |test_key|
              assert_equal normalize_to_json(test_key, attrs[test_key.to_sym]), json[test_key]
            end
          end
        end

        test '#create.json with invalid attributes' do
          attrs = attributes_for(singular_name, :nested, :invalid).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
          create_webmocks(attrs)

          assert_difference("#{model.name}.count", 0) do
            post :create, singular_name => attrs, :format => 'json'
            assert_response :bad_request
            json = JSON.parse(response.body)
            assert json.is_a?(Hash)
            assert json['errors']
          end
        end

        test '#create.json params[:include]' do
          attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
          create_webmocks(attrs)

          assert_difference("#{model.name}.count") do
            post :create, singular_name => attrs, include: includes, :format => 'json'
            assert_response :created
            assert assigns(singular_name)
          
            json = JSON.parse(response.body)
            assert json.is_a?(Hash)
            includes.each do |included|
              assert json.key?(included.to_s), "#{included.inspect} not included in response"
            end
          end
        end

        test 'route to #create.json' do
          assert_routing({ method: :post, path: "/#{plural_name}" }, path_with_action('create'))
          assert_recognizes(path_with_action('create'), { method: :post, path: "/#{plural_name}" })
        end
        
      end
    end
  end
end
