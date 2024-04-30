require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"
Bundler.require(*Rails.groups)

require 'standard_api'

# Test Application Config
Rails.env = 'test'

class TestApplication < Rails::Application
  config.root = File.join(File.dirname(__FILE__), 'test_app')
  config.secret_key_base = 'test key base'
  config.eager_load = true
  config.cache_classes = true
  config.action_controller.perform_caching = true
  config.cache_store = :memory_store, { size: 8.megabytes }
  config.action_dispatch.show_exceptions = :none

  # if defined?(FactoryBotRails)
  #   config.factory_bot.definition_file_paths += [ '../factories' ]
  # end
end

# Test Application initialization
TestApplication.initialize!

# Make sure to test the right view files
ActionView::Template.unregister_template_handler :streamer, :jbuilder
case ENV["TSENCODER"]
when "turbostreamer"
  ActionView::Template.register_template_handler :streamer, TurboStreamer::Handler
else
  ActionView::Template.register_template_handler :jbuilder, JbuilderHandler
end

# Test Application Models
require 'standard_api/test_app/models'

# Test Application Controllers
require 'standard_api/test_app/controllers'

# Test Application Routes
Rails.application.routes.draw do
  get :tables, to: 'application#tables', as: :tables
  get :schema, to: 'application#schema', as: :schema

  [:properties, :photos, :documents, :references, :sessions, :unlimited, :default_limit].each do |r|
    standard_resources r
  end

  standard_resource :account
  # standard_resources :photos, only: [ :index, :show ]

end

# Test Application Helpers
Object.const_set(:ApplicationHelper, Module.new)

# require 'turbostreamer'
# require 'wankel'
# ActionView::Template.unregister_template_handler :jbuilder
# ActionView::Template.register_template_handler :streamer, TurboStreamer::Handler
