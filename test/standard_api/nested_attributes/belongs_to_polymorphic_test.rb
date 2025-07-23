require 'standard_api/test_helper'

module NestedAttributes
  class BelongsToPolymorphicTest < ActionDispatch::IntegrationTest
    # include StandardAPI::TestCase
    include StandardAPI::Helpers

    # = Create Test

    # TODO: we maybe should return an error response when something is filtered
    # out of a create or update
    test 'create record and nested polymorphic record not created because rejected by the ACL' do
      @controller = AccountsController.new

      assert_nothing_raised do
        post account_path, params: { account: { name: 'Smee', subject: {make: 'Nokia'}, subject_type: 'Camera' } }, as: :json
      end
    end

  end
end
