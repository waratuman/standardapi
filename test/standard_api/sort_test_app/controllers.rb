class ApplicationController < ActionController::Base
  include StandardAPI::Controller
  include StandardAPI::AccessControlList
  prepend_view_path File.join(File.dirname(__FILE__), 'views')

  helper_method :serialize_attribute

  def serialize_attribute(json, record, attribute, type)
    value = if attribute == 'description' && params["magic"] === "true"
      'See it changed!'
    else
      record.send(attribute)
    end

    json.set! attribute, type == :binary ? value&.unpack1('H*') : value
  end

end

class AccountsController < ApplicationController

  def show
    @account = Account.last
  end

end

class OrdersController < ApplicationController

  def order_orders
    [ :id, :account_id, :price ]
  end

end
