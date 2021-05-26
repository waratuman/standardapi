module StandardAPI
  module TestCase
    module CalculateTests
      extend ActiveSupport::Testing::Declarative

      CALCULATE_COLUMN_TYPES = [
        "smallint", "int", "integer", "bigint", "real", "double precision",
        "numeric", "interval"
      ]

      test '#calculate.json' do
        create_model

        math_column = model.columns.find { |x| CALCULATE_COLUMN_TYPES.include?(x.sql_type) }

        if math_column
          column = math_column
          selects = [{ count: column.name }, { maximum: column.name }, { minimum: column.name }, { average: column.name }]
        else
          column = model.columns.sample
          selects = [{ count: column.name }]
        end

        get resource_path(:calculate, select: selects, format: :json)
        assert_response :ok
        calculations = @controller.instance_variable_get('@calculations')
        expectations = selects.map { |s| model.send(s.keys.first, column.name) }
        expectations = [expectations] if expectations.length > 1

        if math_column
          assert_equal expectations.map { |a| a.map { |b| b.round(9) } },
            calculations.map { |a| a.map { |b| b.round(9) } }
        else
          assert_equal expectations.map { |b| b.round(9) },
            calculations.map { |b| b.round(9) }
        end
      end

      test '#calculate.json params[:where]' do
        m1 = create_model
        create_model

        math_column = model.columns.find { |x| CALCULATE_COLUMN_TYPES.include?(x.sql_type) }

        if math_column
          column = math_column
          selects = [{ count: column.name}, { maximum: column.name }, { minimum: column.name }, { average: column.name }]
        else
          column = model.columns.sample
          selects = [{ count: column.name}]
        end

        predicate = { id: { gt: m1.id } }

        get resource_path(:calculate, where: predicate, select: selects, format: :json)
        assert_response :ok
        calculations = @controller.instance_variable_get('@calculations')
        # assert_equal [selects.map { |s| model.send(s.keys.first, column.name) }],
        #   calculations
      end

      test '#calculate.json mask' do
        # This is just to instance @controller
        get resource_path(:calculate)

        # If #current_mask isn't defined by StandardAPI we don't know how to
        # test other's implementation of #current_mask. Return and don't test.
        return if @controller.method(:current_mask).owner != StandardAPI

        m = create_model

        @controller.define_singleton_method(:current_mask) do |table_name|
          { id: m.id + 100 }
        end
        selects = [{ count: :id}, { maximum: :id }, { minimum: :id }, { average: :id }]
        get :calculate, select: selects, format: 'json'
        assert_response :ok
        assert_equal [[0, nil, nil, nil]], @controller.instance_variable_get('@calculations')
      end

    end
  end
end
