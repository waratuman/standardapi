class ApplicationController < ActionController::Base
  include StandardAPI::Controller
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
end

class PhotosController < ApplicationController
end

class ReferencesController < ApplicationController
end

class SessionsController < ApplicationController
  # Signs in as params[:user_id], for the Policies that read the session
  def create
    session[:user_id] = params[:user_id].to_i if params[:user_id]
  end
end

# What StandardAPI::TestCase has to cope with (test_case_test.rb): an
# attribute only writable on create, one the Policy assigns whatever the
# params send, and what can be ordered by and filtered on depending on the
# session, which a controller only has with a request.
#
# An app's Policy would call `session`, which it delegates to the
# controller; test_helper.rb includes ActionDispatch::TestProcess into
# Object, whose own `session` would answer here instead. It's found by name,
# like the Policies in test_app.rb, so the tests that stub the nested ones
# still find it.
class NotePolicy < StandardAPI::Policy
  attributes :id, :author_id
  attribute :id, orderable: true, filterable: true
  attribute :title, writable: { on: :create }
  attribute :body, writable: true
  assign :author_id, with: -> { controller.session[:user_id] }
  attribute :rank, orderable: true, filterable: true, if: -> { controller.session[:user_id].present? }
end

class NotesController < ApplicationController
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

  # A photo, for a requester it's hidden from: no format or created_at, nor
  # the email of its account
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

    attributes :make, :hidden, :retired, :photo_id, writable: true

    private

    # `photos/_photo` is a custom partial, so the photo is only rendered
    # with it because that partial passes it to record_policy. The account goes one level
    # deeper, into application/_record.
    #
    # The headers stand in for a Policy that varies by *requester* (current
    # user, role, token); it's chosen once a request, so can't read record.
    # That is the case fragment caching has to defend against, since the
    # cache keys are built from record timestamps alone and cannot tell two
    # requesters apart.
    def photo_policy
      if request.headers['X-Hide-Photo'] == '1'
        HiddenPhotoPolicy
      elsif request.headers['X-Hide-Photo-Format'] == '1'
        PhotoWithoutFormatPolicy
      end
    end
  end

end
