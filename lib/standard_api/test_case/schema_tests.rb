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

        definitions = @controller.schemas_for(model)
        assert_equal definitions.map { |d| d[:name] }.sort, json['attributes'].keys.sort

        definitions.each do |definition|
          actual = json['attributes'][definition[:name]]
          assert_not_nil actual['type'], "Missing `type` for \"#{model}\" attribute \"#{definition[:name]}\"" if definition[:type]
          assert_equal_or_nil definition[:primary_key], actual['primary_key']
          assert_equal_or_nil definition[:null], actual['null']
          assert_equal_or_nil definition[:array], actual['array']
          assert_equal_or_nil definition[:comment], actual['comment']
          assert_equal_or_nil definition[:default].as_json, actual['default']
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
