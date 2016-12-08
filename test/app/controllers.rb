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

  def self.property_orders
    ["id", "name", "aliases", "description", "constructed", "size", "created_at", "active"]
  end

  def self.property_includes
    [:photos, :landlord, :english_name]
  end

end

class AccountsController < ApplicationController

  private

  def account_params
    [ :account_id, :format ]
  end
  
  def self.account_orders
    [:id]
  end

  def self.account_includes
    [:photos]
  end

end

class DocumentsController < ApplicationController
end

class PhotosController < ApplicationController

  def photo_params
    [ :id, :account_id, :property_id, :format ]
  end

  def self.photos_orders
    [:id]
  end

  def self.photos_includes
    [:account]
  end

end

class ReferencesController < ApplicationController
end

class SessionsController < ApplicationController
end

class UnlimitedController < ApplicationController

  def self.model
    Account
  end

  def resource_limit
    nil
  end

end