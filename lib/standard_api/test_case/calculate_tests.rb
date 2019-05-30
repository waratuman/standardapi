module StandardAPI
  module TestCase
    module CalculateTests
      extend ActiveSupport::Testing::Declarative

      test '#calculate.json' do
        create_model
        selects = [{ count: :id}, { maximum: :id }, { minimum: :id }, { average: :id }]

        get resource_path(:calculate, select: selects, format: :json)
        assert_response :ok
        calculations = @controller.instance_variable_get('@calculations')
        assert_equal [[model.count(:id), model.maximum(:id), model.minimum(:id), model.average(:id).to_f]], calculations
      end

      test '#calculate.json params[:where]' do
        m1 = create_model
        create_model

        selects = [{ count: :id}, { maximum: :id }, { minimum: :id }, { average: :id }]
        predicate = { id: { gt: m1.id } }
        get resource_path(:calculate, where: predicate, select: selects, format: :json)

        # assert_response :ok
        # assert_equal [[
        #   model.filter(predicate).count(:id),
        #   model.filter(predicate).maximum(:id),
        #   model.filter(predicate).minimum(:id),
        #   model.filter(predicate).average(:id).to_f
        # ]], @controller.instance_variable_get('@calculations')
      end

      test '#calculate.json mask' do
        # This is just to instance @controller
        get resource_path(:calculate)

        # If #current_mask isn't defined by StandardAPI we don't know how to
        # test other's implementation of #current_mask. Return and don't test.
        return if @controller.method(:current_mask).owner != StandardAPI

        m = create_model

        @controller.current_mask[plural_name] = { id: m.id + 100 }
        selects = [{ count: :id}, { maximum: :id }, { minimum: :id }, { average: :id }]
        get :calculate, select: selects, format: 'json'
        assert_response :ok
        assert_equal [[0, nil, nil, nil]], @controller.instance_variable_get('@calculations')
        @controller.current_mask.delete(plural_name)
      end

    end
  end
end
