module StandardAPI
  module TestCase
    module NewTests
      extend ActiveSupport::Testing::Declarative

      test '#new.json' do
        get :new, format: 'json'
        assert_response :ok
        assert assigns(singular_name)
      end

    end
  end
end
