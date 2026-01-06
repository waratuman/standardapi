module StandardAPI
  module TestCase
    module IndexTests
      extend ActiveSupport::Testing::Declarative

      test '#schema.json' do
        create_model

        get resource_path(:schema, format: :json)
        assert_response :ok
        json = JSON(@response.body)
        assert json['attributes']

        model.columns.map do |column|
          actual_column = json['attributes'][column.name]
          assert_not_nil actual_column['type'], "Missing `type` for \"#{model}\" attribute \"#{column.name}\""
          assert_equal_or_nil model.primary_key == column.name, actual_column['primary_key']
          assert_equal_or_nil column.null, actual_column['null']
          assert_equal_or_nil column.array, actual_column['array']
          assert_equal_or_nil column.comment, actual_column['comment']

          if !column.default.nil?
            default = column.fetch_cast_type(model.connection).deserialize(column.default)
            assert_equal default, actual_column['default']
          else
            assert_nil actual_column['default']
          end
        end

        assert json['limit']
        assert_equal_or_nil model.connection.table_comment(model.table_name), json['comment']
      end

      def assert_equal_or_nil(expected, actual, msg=nil)
        if expected.nil?
          assert_nil actual, msg
        else
          assert_equal expected, actual, msg
        end
      end
    end
  end
end
