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

class Account < ActiveRecord::Base
  
  has_many :photos
  
end

class Photo < ActiveRecord::Base
  
  belongs_to :account, :counter_cache => true
  has_and_belongs_to_many :properties

end

class Property < ActiveRecord::Base

  has_many :photos

end
