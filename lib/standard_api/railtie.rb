module StandardAPI
  class Railtie < ::Rails::Railtie

    initializer 'standardapi', :before => :set_autoload_paths do |app|
      if app.root.join('app', 'controllers', 'acl').exist?
        ActiveSupport::Inflector.inflections(:en) do |inflect|
          inflect.acronym 'ACL'
        end

        app.config.autoload_paths << app.root.join('app', 'controllers', 'acl').to_s
      end

      ActiveSupport.on_load(:before_configuration) do
        ::ActionDispatch::Routing::Mapper.send :include, StandardAPI::RouteHelpers
      end

      ActiveSupport.on_load(:action_view) do
        ::ActionView::Base.send :include, StandardAPI::Helpers
      end
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
