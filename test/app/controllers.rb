class ApplicationController < ActionController::Base
  include StandardAPI::Controller
end

class PropertiesController < ApplicationController

  private

  def property_params
    [ :name,
      :aliases,
      :description,
      :constructed,
      :size,
      :active,
      :photos_attributes,
      { photos_attributes: [ :id, :account_id, :property_id, :format] }
    ]
  end

  def property_orders
    ["id", "name", "aliases", "description", "constructed", "size", "created_at", "active"]
  end

  def property_includes
    [:photos]
  end

end
