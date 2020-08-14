# frozen_string_literal: true

module StandardAPI
  class Railtie < ::Rails::Railtie

    initializer 'standardapi' do
      ActiveSupport.on_load(:action_view) do
        ::ActionView::Base.send :include, StandardAPI::Helpers
        ::ActionDispatch::Routing::Mapper.send :include, StandardAPI::RouteHelpers
      end
    end

  end
end
