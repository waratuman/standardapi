class ApplicationController < ActionController::Base
  include StandardAPI::Controller
  prepend_view_path File.join(File.dirname(__FILE__), 'views')
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
    [:photos, :landlord, :english_name]
  end

end


class PhotosController < ApplicationController

  def photo_params
    [ :id, :account_id, :property_id, :format ]
  end

  def photos_orders
    [:id]
  end

  def photos_includes
    [:account]
  end

end

class ReferencesController < ApplicationController
end