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
require 'standard_api/wheres'
require 'standard_api/excludes'
require 'standard_api/controller'
require 'standard_api/helpers/json_schema_helper'
require 'standard_api/helpers'
require 'standard_api/route_helpers'
require 'standard_api/active_record/connection_adapters/column'
require 'standard_api/active_record/connection_adapters/abstract/schema_statements'
require 'standard_api/railtie'

module StandardAPI
  autoload :AccessControlList, 'standard_api/access_control_list'
  autoload :Schemas, 'standard_api/schemas'
  autoload :Middleware, 'standard_api/middleware'

  def self.included(base)
    base.include StandardAPI::Controller
    base.include StandardAPI::AccessControlList
    base.include StandardAPI::Schemas
  end
end

::ActiveRecord::ConnectionAdapters::SchemaStatements.include StandardAPI::ActiveRecord::ConnectionAdapters::SchemaStatements
::ActiveRecord::ConnectionAdapters::Column.include StandardAPI::ActiveRecord::ConnectionAdapters::Column
