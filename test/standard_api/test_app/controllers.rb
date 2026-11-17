class ApplicationController < ActionController::Base
  include StandardAPI::Controller
  include StandardAPI::AccessControlList
  prepend_view_path File.join(File.dirname(__FILE__), 'views')
  
  helper_method :serialize_attribute

  def serialize_attribute(json, record, attribute, type)
    value = if attribute == 'description' && params["magic"] === "true"
      'See it changed!'
    else
      helpers.attribute_value(record, attribute)
    end
    
    json.set! attribute, type == :binary ? value&.unpack1('H*') : value
  end

end

class PropertiesController < ApplicationController
end

class AccountsController < ApplicationController

  def show
    @account = Account.last
  end

  # A row mask that varies by *requester* rather than by record, which is what
  # the view caching guards have to defend against.
  def mask_for(table_name)
    if table_name.to_s == 'photos' && request.headers['X-Hide-Photos'] == '1'
      { id: -1 }
    end
  end

end

class DocumentsController < ApplicationController

  module ACL

    def attributes(document=nil)
      document&.type == "movie" ? [
        :file, :type, :rating
      ] : [
        :file, :type
      ]
    end

  end

end

class PhotosController < ApplicationController

  def photo_attributes(record = nil)
    [ :id, :account_id, :property_id, :format ]
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

class UuidModelController < ApplicationController
end

class CamerasController < ApplicationController

  # An account, without its email
  class AccountWithoutEmailPolicy < AccountPolicy
    remove :email
  end

  # A photo, without its format
  class PhotoWithoutFormatPolicy < PhotoPolicy
    remove :format
  end

  # The photo of a hidden camera: no format or created_at, nor the email of
  # its account
  class HiddenPhotoPolicy < PhotoPolicy
    remove :format, :created_at
    association :account, policy: AccountWithoutEmailPolicy
  end

  # Adjusts the attribute definitions record_policy(Camera).attributes, the JSON Schemas and
  # rendered cameras are built from, and hides per record what the Camera tests
  # exercise in isolation from Property/Account, which are exercised by the
  # much larger StandardAPI::TestCase generic suite.
  class Policy < StandardAPI::Policy
    attributes :id, :photo_id, :hidden, :retired, :photo_cached_at
    attribute :make, comment: 'The manufacturer', unless: -> { record&.hidden? }
    association :photo, unless: -> { record&.retired? }, policy: :photo_policy
    association :specs

    attributes :id, :make, filterable: true
    attribute :photo_id, filterable: [:eq, :in]
    association :photo, filterable: true

    private

    # `photos/_photo` is a custom partial, so the photo is only rendered
    # with it because that partial passes it to record_policy. The account goes one level
    # deeper, into application/_record.
    #
    # The header stands in for a Policy that varies by *requester* (current
    # user, role, token) rather than by record. That is the case fragment
    # caching has to defend against, since the cache keys are built from
    # record timestamps alone and cannot tell two requesters apart.
    def photo_policy
      if record&.hidden?
        HiddenPhotoPolicy
      elsif request.headers['X-Hide-Photo-Format'] == '1'
        PhotoWithoutFormatPolicy
      end
    end
  end

end
