module StandardAPI
  class Railtie < ::Rails::Railtie

    initializer 'standardapi', before: :set_autoload_paths do |app|
      # Left over from AccessControlList, whose files aren't named for
      # Zeitwerk, so eager loading the controllers would raise
      acl_dir = app.root.join('app', 'controllers', 'acl')
      Rails.autoloaders.main.ignore(acl_dir.to_s) if acl_dir.exist?

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

    # A controller's nested Policy is only found once the controller is
    # loaded, so load them all before registering them. This runs after boot
    # (ahead of config.eager_load) and again after every reload, rather than
    # when the base controller includes Policies: loading subclasses while
    # its class body is still being evaluated would leave them without any
    # callbacks declared after the include.
    config.to_prepare do
      controllers = Rails.application.root.join('app', 'controllers')
      Rails.autoloaders.main.eager_load_dir(controllers.to_s) if controllers.exist?
      StandardAPI::Policies.load!
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
