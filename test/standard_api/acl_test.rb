require 'standard_api/test_helper'

class ACLTest < ActionDispatch::IntegrationTest

  test 'renames a parameter' do
    @controller = KeywordsController.new
    post keywords_path, params: {
      keyword: {
        name: 'Big Ben',
        transaction: { name: "Transaction -> Transaxtion" }
      }
    }, as: :json

    assert_response :created
    keyword = Keyword.last
    assert_equal "Transaction -> Transaxtion", keyword.transaxtion.name
  end

end
