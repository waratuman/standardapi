# = Models

class Account < ActiveRecord::Base
  has_many :photos, -> { order(:created_at) }
  belongs_to :property
  belongs_to :subject, polymorphic: true
  
  validates :name, presence: true
end

class Photo < ActiveRecord::Base
  belongs_to :account, counter_cache: true
  has_and_belongs_to_many :properties
  has_one :camera
end

class Document < ActiveRecord::Base
  attr_accessor :file
end

class Pdf < Document
end

class Property < ActiveRecord::Base
  has_and_belongs_to_many :photos
  has_many :accounts
  has_one :landlord, class_name: 'Account'
  has_one :document_attachments, class_name: "Attachment", as: :record, inverse_of: :record
  has_one :document, through: "document_attachments"

  validates :name, presence: true
  accepts_nested_attributes_for :photos

  def english_name
    'A Name'
  end
end

class LSNType < ActiveRecord::Type::Value

  def type
    :lsn
  end

  def cast_value(value)
    case value
    when Integer
      [value].pack('N')
    else
      value&.to_s&.b
    end
  end

  def serialize(value)
    PG::TextEncoder::Bytea.new.encode(value)
  end

  def deserialize(value)
    return nil if value.nil?
    PG::TextDecoder::Bytea.new.decode(value).unpack1('N')
  end

end

class Reference < ActiveRecord::Base
  belongs_to :subject, polymorphic: true

  attribute :custom_binary, LSNType.new
end

class Document < ActiveRecord::Base
  attr_accessor :file
end

class Attachment < ActiveRecord::Base
  belongs_to :record, polymorphic: true
  belongs_to :document
end

class Camera < ActiveRecord::Base
  
  validates :make, presence: true
  
end

# = Migration

class CreateModelTables < ActiveRecord::Migration[6.0]

  def self.up

    comment = "test comment"
    exec_query(<<-SQL, "SQL")
      COMMENT ON DATABASE #{quote_column_name(current_database)} IS #{quote(comment)};
    SQL

    create_table "accounts", force: :cascade do |t|
      t.string   'name',                 limit: 255
      t.integer  'property_id'
      t.integer  "subject_id"
      t.string   "subject_type"
      t.datetime "property_cached_at"
      t.datetime "subject_cached_at"
      t.integer  'photos_count', null: false, default: 0
      t.datetime "created_at",                         null: false
    end

    create_table "landlords", force: :cascade do |t|
      t.string  "name"
    end

    create_table "photos", force: :cascade do |t|
      t.integer  "account_id"
      t.integer  "property_id"
      t.string   "format",                 limit: 255
      t.datetime "created_at",                         null: false
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

    create_table "references", force: :cascade do |t|
      t.integer  "subject_id"
      t.string   "subject_type",         limit: 255
      t.binary   "sha"
      t.binary   "custom_binary"
      t.string   "key"
      t.string   "value"
    end

    create_table "photos_properties", force: :cascade do |t|
      t.integer  "photo_id"
      t.integer  "property_id"
      t.index ["photo_id", "property_id"], unique: true
    end

    create_table "landlords_properties", force: :cascade do |t|
      t.integer  "landlord_id"
      t.integer  "property_id"
    end

    create_table "documents", force: :cascade do |t|
      t.string   'type'
    end

    create_table "cameras", force: :cascade do |t|
      t.integer  'photo_id'
      t.string   'make'
    end

    create_table "attachments", force: :cascade do |t|
      t.string  'record_type'
      t.integer  'record_id'
      t.integer  'document_id'
    end
  end

end
ActiveRecord::Migration.verbose = false
CreateModelTables.up
