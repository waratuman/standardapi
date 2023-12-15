require 'standard_api/sort_test_app'
require 'standard_api/test_helper'

class ControllerCustomOrderTest < ActionDispatch::IntegrationTest

  # = Including an invalid include

  test "Controller#index with order name set sort" do
    account = create(:account)
    order = create(:order, account: account)
    account.update(order: order)

    get "/account", params: { include: [ :order, :orders ] }, as: :json
    json = JSON.parse(response.body)

    assert_equal [
      {
        id: order.id,
        account_id: account.id,
        name: order.name,
        price: order.price
      }.stringify_keys
    ],json["orders"]

    assert_equal(
      {
        id: order.id,
        account_id: account.id,
        name: order.name,
        price: order.price
      }.stringify_keys, json["order"])
  end

end
