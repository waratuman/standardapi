require 'rails/all'
Bundler.require(*Rails.groups)

# require 'jbuilder'
# require 'turbostreamer'
# require 'wankel'
require 'standard_api'

# Test Application Config
Rails.env = 'test'
class TestApplication < Rails::Application
  config.root = File.join(File.dirname(__FILE__), 'app')
  config.secret_key_base = 'test key base'
  config.eager_load = false
  config.cache_store = :memory_store, { size: 8.megabytes }
  config.action_dispatch.show_exceptions = false

  if defined?(FactoryBotRails)
    config.factory_bot.definition_file_paths += [ '../factories' ]
  end
end

# Test Application initialization
TestApplication.initialize!

# Test Application Routes
TestApplication.routes.draw do
  get :tables, to: 'application#tables', as: :tables

  [:properties, :photos, :documents, :references, :sessions, :unlimited, :default_limit].each do |r|
    standard_resources r
  end

  standard_resource :account
end

# Test Application Models
require 'app/models'

# Test Application Controllers
require 'app/controllers'

# Test Application Helpers
Object.const_set(:ApplicationHelper, Module.new)
