# frozen_string_literal: true

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
end