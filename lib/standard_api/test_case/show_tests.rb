module ActionController
  class StandardAPI < ActionController::Base
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

          if include_slug_tests && model.attribute_names.include?('slug')
            get :show, id: m.slug, format: 'json'
            assert_response :ok
            assert_template :show
            assert_equal m, assigns(singular_name)
          end
        end

        test '#show.json responds with :not_found after slug update and mask' do
          return if !(include_slug_tests && model.attribute_names.include?('slug'))

          m = create_model
          @api_key.update(mask: { plural_name => { id: m.id + 1 } })

          old_slug = m.slug
          m.update_column(:slug, 'nw/slug')

          get :show, id: old_slug, format: 'json'
          assert_response :not_found
        end

        test '#show.json responds with :moved_permanently after slug update' do
          return if !(include_slug_tests && model.attribute_names.include?('slug'))

          m = create_model
          old_slug = m.slug
          m.update_column(:slug, 'nw/slug')

          get :show, id: old_slug, format: 'json'
          assert_response :moved_permanently
          assert response.headers['Location'] =~ /#{m.slug}.json$/
        end

        test '#show.json responds with :gone after destroyed' do
          return if !(include_slug_tests && model.attribute_names.include?('slug'))

          m = create_model
          m.destroy

          get :show, id: m.id, format: 'json'
          assert_response :gone

          get :show, id: m.slug, format: 'json'
          assert_response :gone
        end

        test '#show.json mask' do
          m = create_model
          @api_key.update(mask: { plural_name => { id: m.id + 1 } })
          get :show, id: m.id, format: 'json'
          assert_equal nil, assigns(singular_name)
        end

        test '#show.json params[:include]' do
          m = create_model

          includes.each do |included|
            get :show, id: m.id, include: [included], format: 'json'
            assert JSON.parse(response.body).key?(included.to_s), "#{included.inspect} not included in response"
          end
        end

        test 'route to #show.json' do
          assert_routing "/#{plural_name}/1", path_with_action('show', id: '1')
          assert_recognizes(path_with_action('show', id: '1'), "/#{plural_name}/1")
        end

      end
    end
  end
end
