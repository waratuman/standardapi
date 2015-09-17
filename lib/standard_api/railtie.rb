module StandardAPI
  class Railtie < ::Rails::Railtie

    initializer 'standardapi' do
      ActiveSupport.on_load(:action_view) do
        ::ActionView::Base.send :include, StandardAPI::Helpers
      end
    end

  end
end