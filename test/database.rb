task = ActiveRecord::Tasks::PostgreSQLDatabaseTasks.new({
  'adapter' => 'postgresql',
  'database' => "activerecord-filter-test"
})
task.drop
task.create

ActiveRecord::Base.establish_connection({
  adapter:  "postgresql",
  database: "activerecord-filter-test",
  encoding: "utf8"
})

ActiveRecord::Migration.suppress_messages do
  ActiveRecord::Schema.define do

    create_table "accounts", force: :cascade do |t|
      t.string   "name",                 limit: 255
      t.integer  'photos_count', null: false, default: 0
    end
    
    create_table "photos", force: :cascade do |t|
      t.integer  "account_id"
      t.integer  "property_id"
      t.string   "format",                 limit: 255
    end
    
    create_table "properties", force: :cascade do |t|
      t.string   "name",                 limit: 255
      t.string   "aliases",              default: [],   array: true
      t.text     "description"
      t.integer  "constructed"
      t.decimal  "size"
      t.datetime "created_at",                         null: false
      t.boolean  "active",             default: false
    end

  end
end

require 'rails'
class TestApplication < Rails::Application

  config.secret_token = 'test token'
  config.secret_key_base = 'test key base'
  
  routes.draw do
    resources :properties do
      get :calculate, on: :collection
    end
  end

end
# all_routes = Rails.application.routes.routes
# require 'action_dispatch/routing/inspector'
# inspector = ActionDispatch::Routing::RoutesInspector.new(all_routes)
# puts inspector.format(ActionDispatch::Routing::ConsoleFormatter.new, ENV['CONTROLLER'])

class Account < ActiveRecord::Base
  has_many :photos
end

class Photo < ActiveRecord::Base
  belongs_to :account, :counter_cache => true
  has_and_belongs_to_many :properties
end

class Property < ActiveRecord::Base
  has_many :photos
  validates :name, presence: true
  accepts_nested_attributes_for :photos
end

class ApplicationController < ActionController::Base
  include StandardAPI
end

class PropertiesController < ApplicationController

  private

  # For testing
  def _routes
    Rails.application.routes
  end

  def property_params
    [ :name,
      :aliases,
      :description,
      :constructed,
      :size,
      :active,
      :photos_attributes,
      { photos_attributes: [ :id, :account_id, :property_id, :format] }
    ]
  end

  def property_orders
    [:id, :updated_at, :created_at, :name]
  end

  def property_includes
    [:photos]
  end

end

# puts PropertiesController.instance_methods.sort
# puts PropertiesController.use_renderers.inspect
# puts PropertiesController.view_paths.exists?('show', ['properties'])
# puts PropertiesController.view_context_class.methods.sort
# puts PropertiesController._renderers.to_a
