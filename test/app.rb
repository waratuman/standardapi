require 'rails/all'

# Test Application Config
Rails.env = 'test'
class TestApplication < Rails::Application
  config.root = File.join(File.dirname(__FILE__), 'app')
  config.secret_token = 'test token'
  config.secret_key_base = 'test key base'
  config.eager_load = false
  config.cache_store = :memory_store, { size: 8.megabytes }
  config.action_dispatch.show_exceptions = false
end

# Test Application initialization
TestApplication.initialize!

# Test Application Routes
TestApplication.routes.draw do
  get :tables, to: 'application#tables', as: :tables
  [:properties, :photos, :documents, :references, :sessions, :unlimited].each do |r|
    standard_resources r do
      get :calculate, on: :collection
      get :schema, on: :collection
    end
  end

  standard_resource :account
end

# Test Application Models
require 'app/models'  

# Test Application Controllers
require 'app/controllers'

# Test Application Helpers
Object.const_set(:ApplicationHelper, Module.new)
