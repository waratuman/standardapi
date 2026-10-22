require 'standard_api/test_helper'

class SchemasTest < ActionDispatch::IntegrationTest

  KEYS = %i(name type enum default primary_key null array comment
    auto_populated read_only required validations)

  def schemas(model, controller: PropertiesController.new)
    controller.schemas_for(model)
  end

  def attribute(model, name, **options)
    schemas(model, **options).find { |a| a[:name] == name }
  end

  test 'one definition per attribute, in attribute order, with every key' do
    definitions = schemas(Property)

    assert_equal Property.attribute_names, definitions.map { |a| a[:name] }
    definitions.each { |a| assert_equal KEYS, a.keys }
  end

  test 'types, defaults and column facts' do
    id = attribute(Property, 'id')
    assert_equal 'integer', id[:type]
    assert_equal true, id[:primary_key]
    assert_equal false, id[:null]

    created_at = attribute(Property, 'created_at')
    assert_equal 'datetime', created_at[:type]
    assert_equal false, created_at[:primary_key]

    assert_equal 2, attribute(Property, 'numericality')[:default]
    assert_equal false, attribute(Property, 'active')[:default]
    assert_nil attribute(Property, 'description')[:default]
  end

  test 'enums are strings, named by their default' do
    level = attribute(Document, 'level', controller: DocumentsController.new)
    assert_equal 'string', level[:type]
    assert_equal ['public', 'secret'], level[:enum]
    assert_equal 'public', level[:default]

    rating = attribute(Document, 'rating', controller: DocumentsController.new)
    assert_nil rating[:default]
    assert_nil attribute(Document, 'type', controller: DocumentsController.new)[:enum]
  end

  test 'comment is the column comment' do
    skip "Adapter does not support column comments" if !postgres? && !mariadb?

    assert_equal 'Ratings are 1-10, where 10 is great',
      attribute(Document, 'rating', controller: DocumentsController.new)[:comment]
  end

  test 'read_only follows the ACL attributes' do
    assert_equal false, attribute(Property, 'name')[:read_only]
    assert_equal true, attribute(Property, 'created_at')[:read_only]
    assert_equal true, attribute(Property, 'id')[:read_only]
  end

  test 'read_only falls back to the model without ACL attributes' do
    # ReferenceACL defines no attributes
    assert_equal false, attribute(Reference, 'key', controller: ReferencesController.new)[:read_only]

    Reference.stubs(:readonly_attribute?).returns(false)
    Reference.stubs(:readonly_attribute?).with('key').returns(true)
    assert_equal true, attribute(Reference, 'key', controller: ReferencesController.new)[:read_only]
  end

  test 'an STI subclass uses the ACL of its base class' do
    controller = DocumentsController.new

    # DocumentsController::ACL permits file and type
    assert_equal controller.model_attributes(Document), controller.model_attributes(Pdf)
    assert_equal false, attribute(Pdf, 'type', controller: controller)[:read_only]
    assert_equal true, attribute(Pdf, 'rating', controller: controller)[:read_only]

    # and so does creating or updating one
    params = ActionController::Parameters.new(type: 'Pdf', rating: 3)
    assert_equal({ 'type' => 'Pdf' }, controller.filter_model_params(Pdf.new, params).to_h)

    controller = DocumentsController.new
    controller.define_singleton_method(:document_schemas) do |default_schema|
      default_schema.map { |s| s[:name] == 'type' ? s.merge(comment: 'From DocumentACL') : s }
    end
    assert_equal 'From DocumentACL', attribute(Pdf, 'type', controller: controller)[:comment]
  end

  test 'a definition the ACL schemas adds is returned as it is' do
    controller = CamerasController.new
    controller.define_singleton_method(:camera_schemas) do |default_schema|
      default_schema + [{ name: 'thumbnail_url', type: 'string' }]
    end

    assert_equal({ name: 'thumbnail_url', type: 'string' }, attribute(Camera, 'thumbnail_url', controller: controller))
  end

  test 'a read only attribute is not required, without ACL attributes' do
    # ReferenceACL defines no attributes, so read_only comes from the model
    Reference.stubs(:readonly_attribute?).returns(false)
    Reference.stubs(:readonly_attribute?).with('key').returns(true)
    # Columns are frozen, so stub a NOT NULL copy of key's
    key_column = Reference.columns_hash['key'].dup
    key_column.stubs(:null).returns(false)
    columns = Reference.columns_hash.merge('key' => key_column)
    Reference.stubs(:columns_hash).returns(columns)

    key = attribute(Reference, 'key', controller: ReferencesController.new)
    assert_equal true, key[:read_only]
    assert_equal false, key[:required]
  end

  test 'required' do
    # presence validation
    assert_equal true, attribute(Property, 'name')[:required]
    # acceptance validation, which allows nil unless told otherwise
    assert_equal false, attribute(Property, 'agree_to_terms')[:required]
    # NOT NULL but read only through the ACL
    assert_equal false, attribute(Property, 'created_at')[:required]
    # nullable without validations
    assert_equal false, attribute(Property, 'description')[:required]
    # NOT NULL and writable
    assert_equal true, attribute(Camera, 'make', controller: CamerasController.new)[:required]
  end

  test 'validations' do
    assert_equal [{ kind: :presence, options: {} }], attribute(Property, 'name')[:validations]
    assert_equal [
      { kind: :format, options: { with: /\d{3}-\d{3}-\d{4}/ } },
      { kind: :length, options: { minimum: 9, maximum: 12, allow_blank: true } }
    ], attribute(Property, 'phone_number')[:validations]
    assert_equal [], attribute(Property, 'description')[:validations]
  end

  test 'definitions are built once per model' do
    controller = PropertiesController.new
    assert_same schemas(Property, controller: controller).first,
      schemas(Property, controller: controller).first
  end

  test 'the ACL schemas method transforms the definitions' do
    # CameraACL#schemas sets a comment on make
    assert_equal 'The manufacturer', attribute(Camera, 'make', controller: CamerasController.new)[:comment]
    assert_nil attribute(Camera, 'hidden', controller: CamerasController.new)[:comment]
  end

  test 'type is the ActiveModel type' do
    assert_equal 'decimal', attribute(Property, 'size')[:type]
    assert_equal 'text', attribute(Property, 'description')[:type]
    assert_equal 'boolean', attribute(Property, 'active')[:type]
    assert_equal 'binary', attribute(Reference, 'sha', controller: ReferencesController.new)[:type]
    # an `attribute` declaration over a binary column
    assert_equal 'lsn', attribute(Reference, 'custom_binary', controller: ReferencesController.new)[:type]
  end

  test 'array columns are typed by their elements' do
    skip "Adapter does not support array columns" if !postgres?

    aliases = attribute(Property, 'aliases')
    assert_equal 'string', aliases[:type]
    assert_equal true, aliases[:array]
  end

  test 'date, time and datetime stay apart' do
    model = Class.new(Property) do
      def self.name = 'Property'
      attribute :opened_on, :date
      attribute :opens_at, :time
      attribute :inspected_at, :datetime
    end

    assert_equal %w(date time datetime), %w(opened_on opens_at inspected_at).map { |name|
      attribute(model, name)[:type]
    }
  end

  test 'an attribute without a column' do
    model = Class.new(Property) do
      def self.name = 'Property'
      attribute :nickname, :string
    end

    definitions = schemas(model)
    assert_equal 'nickname', definitions.last[:name]
    assert_equal({
      name: 'nickname', type: 'string', enum: nil, default: nil,
      primary_key: false, null: nil, array: false, comment: nil,
      auto_populated: nil, read_only: true, required: false, validations: []
    }, definitions.last)
  end

end
