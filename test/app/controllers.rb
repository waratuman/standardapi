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

class AccountsController < ApplicationController

  private

  def account_params
    [ :property_id, :name ]
  end
  
  def account_orders
    [:id]
  end

  def account_includes
    [:photos]
  end

end

class DocumentsController < ApplicationController

  def document_params
    [ :file, :type ]
  end
  
  def document_orders
    [:id]
  end

  def document_includes
    [:photos]
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

class DefaultLimitController < ApplicationController


  def self.model
    Account
  end

  def default_limit
    100
  end

end