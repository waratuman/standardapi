module ActionController
  class StandardAPI < ActionController::Base
    module TestCase
      module UpdateTests
        extend ActiveSupport::Testing::Declarative

        test '#update.json' do
          m = create_model
          attrs = attributes_for(singular_name).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
          create_webmocks(attrs)

          put :update, id: m.id, singular_name => attrs, format: 'json'
          assert_response :ok

          (m.attribute_names & attrs.keys.map(&:to_s)).each do |test_key|
            assert_equal normalize_attribute(test_key, attrs[test_key.to_sym]), m.reload.send(test_key)
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
          m = create_model(:nested)
          attrs = attributes_for(singular_name).select{|k,v| !model.readonly_attributes.include?(k) }
          create_webmocks(attrs)

          put :update, id: m.id, include: includes, singular_name => attrs, format: 'json'

          json = JSON.parse(response.body)
          includes.each do |included|
            assert json.key?(included.to_s), "#{included.inspect} not included in response"

            association = assigns(:record).class.reflect_on_association(included)
            if ['belongs_to', 'has_one'].include?(association.macro)
              assigns(:record).send(included).attributes do |key, value|
                assert_equal json[included.to_s][key.to_s], value
              end
            else
              assigns(:record).send(included).first.attributes.each do |key, value|
                assert_equal json[included.to_s][0][key.to_s], value
              end
            end
          end
        end

        test '#update.json mask' do
          m = create_model
          @controller.current_mask[plural_name] = { id: m.id + 1 }
          assert_raises(ActiveRecord::RecordNotFound) do
            put :update, id: m.id, format: 'json'
          end
          @controller.current_mask.delete(plural_name)
        end

        test 'route to #update.json' do
          assert_routing({ method: :put, path: "#{plural_name}/1" }, path_with_action('update', id: '1'))
          assert_recognizes(path_with_action('update', id: '1'), { method: :put, path: "/#{plural_name}/1" })
          assert_routing({ method: :patch, path: "/#{plural_name}/1" }, path_with_action('update', id: '1'))
          assert_recognizes(path_with_action('update', id: '1'), { method: :patch, path: "/#{plural_name}/1" })
        end

      end
    end
  end
end
