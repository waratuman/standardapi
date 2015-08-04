module ActionController
  class StandardAPI < ActionController::Base
    module TestCase
      module CalculateTests
        extend ActiveSupport::Testing::Declarative

        test '#calculate.json' do
          m = create_model
          selects = [{ count: :id}, { maximum: :id }, { minimum: :id }, { average: :id }]

          get :calculate, select: selects, format: 'json'
          assert_response :ok
          assert_equal [[model.count(:id), model.maximum(:id), model.minimum(:id), model.average(:id).to_f]], assigns(:calculations)
        end

        test '#calculate.json params[:where]' do
          m1 = create_model
          m2 = create_model

          selects = [{ count: :id}, { maximum: :id }, { minimum: :id }, { average: :id }]
          predicate = { id: { gt: m1.id } }

          get :calculate, where: predicate, select: selects, format: 'json'
          assert_response :ok
          assert_equal [[model.filter(predicate).count(:id), model.filter(predicate).maximum(:id), model.filter(predicate).minimum(:id), model.filter(predicate).average(:id).to_f]], assigns(:calculations)
        end

        test '#calculate.json mask' do
          m = create_model
          @controller.current_mask[plural_name] = { id: m.id + 100 }
          selects = [{ count: :id}, { maximum: :id }, { minimum: :id }, { average: :id }]
          get :calculate, select: selects, format: 'json'
          assert_response :ok
          assert_equal [[0, nil, nil, nil]], assigns(:calculations)
          @controller.current_mask.delete(plural_name)
        end

        test 'route to #calculate.json' do
          assert_routing "/#{plural_name}/calculate", path_with_action('calculate')
          assert_recognizes(path_with_action('calculate'), "/#{plural_name}/calculate")
        end
        
      end
    end
  end
end
