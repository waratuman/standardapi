module StandardAPI
  module TestCase
    module IndexTests
      extend ActiveSupport::Testing::Declarative

      test '#schema.json' do
        create_model

        get resource_path(:schema, format: :json)
        assert_response :ok
        json = JSON(@response.body)
        assert json['columns']
        model.columns.map do |column|
          assert json['columns'][column.name]['type']
        end
        assert json['limit']
      end

    end
  end
end