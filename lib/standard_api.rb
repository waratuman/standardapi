require 'rails'
require 'action_view'
require 'action_pack'
require 'action_controller'

require 'active_record/filter'
require 'active_record/sort'
require 'active_support/core_ext/hash/indifferent_access'
require 'action_dispatch'

require 'standard_api/version'
require 'standard_api/errors'
require 'standard_api/orders'
require 'standard_api/includes'
require 'standard_api/controller'
require 'standard_api/helpers'
require 'standard_api/route_helpers'
require 'standard_api/active_record/connection_adapters/postgresql/schema_statements'
require 'standard_api/railtie'

module StandardAPI
  autoload :AccessControlList, 'standard_api/access_control_list'
  autoload :Middleware, 'standard_api/middleware'

  def self.included(base)
    base.include StandardAPI::Controller
    base.include StandardAPI::AccessControlList
  end
end
