# = Models

class Account < ActiveRecord::Base
  has_many :orders
end

class Order < ActiveRecord::Base
  belongs_to :account
end

# = Migration

class CreateModelTables < ActiveRecord::Migration[6.0]

  def self.up
    create_table "accounts", force: :cascade do |t|
      t.string   'name',                 limit: 255
      t.datetime "created_at",                         null: false
      t.datetime "updated_at",                         null: false
    end

    create_table "orders", force: :cascade do |t|
      t.integer "account_id",                          null: false
      t.string  "name",                  limit: 255
      t.integer "price",                               null: false
    end

  end

end

ActiveRecord::Migration.verbose = false
CreateModelTables.up
