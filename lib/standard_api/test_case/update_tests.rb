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
          m = create_model
          attrs = attributes_for(singular_name).select{|k,v| !model.readonly_attributes.include?(k) }
          create_webmocks(attrs)

          put :update, id: m.id, include: includes, singular_name => attrs, format: 'json'
          json = JSON.parse(response.body)
          assert json.is_a?(Hash)
          includes.each do |included|
            assert json.key?(included.to_s), "#{included.inspect} not included in response"
          end
        end

        test '#update.json responds with :not_found after slug update and mask' do
          return if !(include_slug_tests && model.attribute_names.include?('slug'))

          m = create_model
          @api_key.update(mask: { plural_name => { id: m.id + 1 } })

          old_slug = m.slug
          m.update_column(:slug, 'nw/slug')

          put :update, id: old_slug, format: 'json'
          assert_response :not_found
        end

        test '#update.json responds with :moved_permanently after slug update' do
          return if !(include_slug_tests && model.attribute_names.include?('slug'))

          m = create_model
          old_slug = m.slug
          m.update_column(:slug, 'nw/slug')

          put :update, id: old_slug, format: 'json'
          assert_response :moved_permanently
          assert response.headers['Location'] =~ /#{m.slug}.json$/
        end

        test '#update.json responds with :gone after destroyed' do
          return if !(include_slug_tests && model.attribute_names.include?('slug'))

          m = create_model
          m.destroy

          put :update, id: m.id, format: 'json'
          assert_response :gone

          put :update, id: m.slug, format: 'json'
          assert_response :gone
        end

        test '#update.json mask' do
          m = create_model
          @api_key.update(mask: { plural_name => { id: m.id + 1 } })
          put :update, id: m.id, format: 'json'
          assert_equal nil, assigns(singular_name)
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
