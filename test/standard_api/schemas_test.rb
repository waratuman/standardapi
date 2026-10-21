require 'standard_api/test_helper'

class SchemasTest < ActionDispatch::IntegrationTest

  KEYS = %i(name type enum default primary_key null array description
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

  test 'description is the column comment' do
    skip "Adapter does not support column comments" if !postgres? && !mariadb?

    assert_equal 'Ratings are 1-10, where 10 is great',
      attribute(Document, 'rating', controller: DocumentsController.new)[:description]
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
      primary_key: false, null: nil, array: false, description: nil,
      auto_populated: nil, read_only: true, required: false, validations: []
    }, definitions.last)
  end

end
