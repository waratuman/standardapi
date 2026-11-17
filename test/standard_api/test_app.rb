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
  config.enable_reloading = false
  config.action_controller.perform_caching = true
  config.cache_store = :memory_store, { size: 8.megabytes }
  config.action_dispatch.show_exceptions = :none

  def config.database_configuration
    case ENV.fetch("DB_ADAPTER", "postgresql")
    when 'sqlite', 'sqlite3'
      { "test" => {
        "adapter" => 'sqlite3',
        "database" => ":memory:"
      } }
    when 'postgresql'
      { "test" => {
        "adapter" => "postgresql",
        "database" => "standardapi-test",
        "encoding" => "utf8"
      } }
    else
      raise "Unsupported DB_ADAPTER: #{ENV["DB_ADAPTER"]}"
    end
  end

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

# Every model the tests render declares all of its attributes, by name, as
# most tests aren't about Policies, and what can be included and ordered by of
# it. Before the controllers, whose Policies inherit from them.
{
  Account => -> {
    attribute :id, orderable: true
    association :photos
    association :property, orderable: true
    association :subject, types: ['Property']
  },
  Photo => -> {
    attributes :id, :created_at, :account_id, orderable: true
    associations :account
  },
  Property => -> {
    attributes :id, :name, :aliases, :description, :constructed, :size, :created_at, :active,
      :numericality, :build_type, :phone_number, :agree_to_terms, orderable: true
    associations :photos, :landlord, :english_name, :document, :accounts
  },
  Reference => -> { association :subject, types: ['Property'] },
  Document => -> { attribute :id, orderable: true },
  Attachment => -> {},
  UuidModel => -> {}
}.each do |model, includes|
  names = model.attribute_names
  Object.const_set("#{model.name}Policy", Class.new(StandardAPI::Policy) {
    attributes(*names)
    class_exec(&includes)
  })
end

# Test Application Controllers
require 'standard_api/test_app/controllers'

# The controllers above are defined after boot, outside app/controllers, so the
# Railtie never saw their nested ACLs and Policies.
StandardAPI::AccessControlList.load!
StandardAPI::Policies.load!

# Test Application Routes
Rails.application.routes.draw do
  get :tables, to: 'application#tables', as: :tables
  get :schema, to: 'application#schema', as: :schema

  [:properties, :photos, :documents, :references, :sessions, :unlimited, :default_limit, :cameras].each do |r|
    standard_resources r
  end

  standard_resource :account
  standard_resources :accounts, only: :index
  # standard_resources :photos, only: [ :index, :show ]

end

# Test Application Helpers
Object.const_set(:ApplicationHelper, Module.new)

# require 'turbostreamer'
# require 'wankel'
# ActionView::Template.unregister_template_handler :jbuilder
# ActionView::Template.register_template_handler :streamer, TurboStreamer::Handler
