module StandardAPI
  class Railtie < ::Rails::Railtie

    initializer 'standardapi', before: :set_autoload_paths do |app|
      if app.root.join('app', 'controllers', 'acl').exist?
        ActiveSupport::Inflector.inflections(:en) do |inflect|
          inflect.acronym 'ACL'
        end

        app.config.autoload_paths << app.root.join('app', 'controllers', 'acl').to_s
      end

      ActiveSupport.on_load(:before_configuration) do
        ::ActionDispatch::Routing::Mapper.include StandardAPI::RouteHelpers
      end

      ActiveSupport.on_load(:action_view) do
        ::ActionView::Base.include StandardAPI::Helpers
      end

      # Deferred so apps without Postgres aren't forced to load the `pg` gem
      ActiveSupport.on_load(:active_record_postgresqladapter) do
        require 'standard_api/active_record/connection_adapters/postgresql/schema_statements'
        include StandardAPI::ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaStatements
      end
    end

    # A controller's nested ACL module is only found once the controller is
    # loaded, so load them all before including the ACLs. This runs after boot
    # (ahead of config.eager_load) and again after every reload, rather than
    # when the base controller includes AccessControlList: loading subclasses
    # while its class body is still being evaluated would leave them without
    # any callbacks declared after the include.
    config.to_prepare do
      controllers = Rails.application.root.join('app', 'controllers')
      Rails.autoloaders.main.eager_load_dir(controllers.to_s) if controllers.exist?
      StandardAPI::AccessControlList.load! if !StandardAPI::AccessControlList.base_controllers.empty?
    end

  end
  
  module AutosaveByDefault
    def self.included base
      base.class_eval do
        class <<self  
          alias_method :standard_build, :build
        end
      
        def self.build(model, name, scope, options, &block)
          options[:autosave] = true
          standard_build(model, name, scope, options, &block)
        end
      end
    end
  end

  ::ActiveRecord::Associations::Builder::Association.include(AutosaveByDefault)
end
