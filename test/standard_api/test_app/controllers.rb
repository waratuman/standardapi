class ApplicationController < ActionController::Base
  include StandardAPI::Controller
  include StandardAPI::AccessControlList
  prepend_view_path File.join(File.dirname(__FILE__), 'views')
  
  helper_method :dump_attribute

  def dump_attribute(record, attribute)
    return 'See it changed!' if attribute.to_sym == :description && params["magic"] === "true"
    record.send(attribute)
  end

end

class PropertiesController < ApplicationController
end

class AccountsController < ApplicationController

  def show
    @account = Account.last
  end

end

class DocumentsController < ApplicationController

  def document_attributes
    [ :file, :type ]
  end

  def document_orders
    [ :id ]
  end

end

class PhotosController < ApplicationController

  def photo_attributes
    [ :id, :account_id, :property_id, :format ]
  end

  def photo_orders
    [ :id ]
  end

  def photo_includes
    [ :account ]
  end

end

class ReferencesController < ApplicationController
end

class SessionsController < ApplicationController
  def create
  end
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
