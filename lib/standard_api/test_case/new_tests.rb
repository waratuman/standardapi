module StandardAPI
  module TestCase
    module NewTests
      extend ActiveSupport::Testing::Declarative

      test '#new.json' do
        get resource_path(:new, format: 'json')
        assert_response :ok
        assert @controller.instance_variable_get("@#{singular_name}")
      end

    end
  end
end
