require 'rails/all'

# Test Application Config
Rails.env = 'test'
class TestApplication < Rails::Application
  config.secret_token = 'test token'
  config.secret_key_base = 'test key base'
  config.eager_load = false
  config.root = File.join(File.dirname(__FILE__), 'app')
end

# Test Application initialization
TestApplication.initialize!

# Test Application Routes
TestApplication.routes.draw do
  resources :properties do
    get :calculate, on: :collection
    get :schema, on: :collection
  end
end

# Test Application Models
require 'app/models'  

# Test Application Controllers
require 'app/controllers'

# Test Application Helpers
Object.const_set(:ApplicationHelper, Module.new)
