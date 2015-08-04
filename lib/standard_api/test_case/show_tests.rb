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
        end

        test '#show.json mask' do
          m = create_model
          @controller.current_mask[plural_name] = { id: m.id + 1 }
          assert_raises(ActiveRecord::RecordNotFound) do
            get :show, id: m.id, format: 'json'
          end
          @controller.current_mask.delete(plural_name)
        end

        test '#show.json params[:include]' do
          m = create_model(:nested)
          get :show, id: m.id, include: includes, format: 'json'

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

        test 'route to #show.json' do
          assert_routing "/#{plural_name}/1", path_with_action('show', id: '1')
          assert_recognizes(path_with_action('show', id: '1'), "/#{plural_name}/1")
        end

      end
    end
  end
end

