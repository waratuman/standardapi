require 'standard_api/sort_test_app'
require 'standard_api/test_helper'

class ControllerCustomOrderTest < ActionDispatch::IntegrationTest

  # = Including an invalid include

  test "Controller#index with order name set sort" do
    account = create(:account)
    order = create(:order, account: account)
    account.update(order: order)

    get "/account", params: { include: { order: true, orders: { account: { order: true } } } }, as: :json
    json = JSON.parse(response.body)

    assert_equal [
      {
        id: order.id,
        account_id: account.id,
        name: order.name,
        price: order.price,
        account: {
          id: account.id,
          name: account.name,
          order_id: account.order_id,
          created_at: account.created_at,
          updated_at: account.updated_at,
          order: {
            id: order.id,
            account_id: account.id,
            name: order.name,
            price: order.price
          }
        }
      }
    ].to_json, json["orders"].to_json

    assert_equal(
      {
        id: order.id,
        account_id: account.id,
        name: order.name,
        price: order.price
      }.stringify_keys, json["order"])
  end

end
