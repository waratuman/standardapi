module StandardAPI
  module TestCase
    module CalculateTests
      extend ActiveSupport::Testing::Declarative

      CALCULATE_COLUMN_TYPES = ["smallint", "int", "bigint", "real", "double precision", "numeric", "interval"]

      test '#calculate.json' do
        create_model

        column = model.columns.find { |x| CALCULATE_COLUMN_TYPES.include?(x.sql_type) }.name
        selects = [{ count: column}, { maximum: column }, { minimum: column }, { average: column }]

        get resource_path(:calculate, select: selects, format: :json)
        assert_response :ok
        calculations = @controller.instance_variable_get('@calculations')
        assert_equal [[model.count(column), model.maximum(column), model.minimum(column), model.average(column).to_f]], calculations
      end

      test '#calculate.json params[:where]' do
        m1 = create_model
        create_model

        column = model.columns.find { |x| CALCULATE_COLUMN_TYPES.include?(x.sql_type) }.name
        selects = [{ count: column}, { maximum: column }, { minimum: column }, { average: column }]
        predicate = { id: { gt: m1.id } }

        get resource_path(:calculate, where: predicate, select: selects, format: :json)

        # assert_response :ok
        # assert_equal [[
        #   model.filter(predicate).count(column),
        #   model.filter(predicate).maximum(column),
        #   model.filter(predicate).minimum(column),
        #   model.filter(predicate).average(column).to_f
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
