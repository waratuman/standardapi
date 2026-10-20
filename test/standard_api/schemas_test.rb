require 'standard_api/test_helper'

class SchemasTest < ActionDispatch::IntegrationTest

  KEYS = %i(name type sql_type cast_type enum default primary_key null array
    description auto_populated read_only required validations)

  def schemas(model_or_record, controller: PropertiesController.new)
    controller.schemas(model_or_record)
  end

  def attribute(model, name, **options)
    schemas(model, **options).find { |a| a[:name] == name }
  end

  test 'one definition per column, in column order, with every key' do
    definitions = schemas(Property)

    assert_equal Property.column_names, definitions.map { |a| a[:name] }
    definitions.each { |a| assert_equal KEYS, a.keys }
  end

  test 'types, defaults and column facts' do
    id = attribute(Property, 'id')
    assert_equal 'integer', id[:type]
    assert_equal :integer, id[:cast_type]
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
    assert_equal :integer, level[:cast_type]
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

  test 'a record is described by its loaded attributes' do
    create(:property)
    record = Property.select(:id, :name, 'LENGTH(name) AS name_length').first

    definitions = schemas(record)
    assert_equal ['id', 'name', 'name_length'], definitions.map { |a| a[:name] }
    assert_equal KEYS, definitions.last.keys

    assert_equal 'string', definitions[1][:type]
    assert_nil definitions[1][:read_only]
    assert_nil definitions[1][:required]

    assert_nil definitions.last[:type]
    assert_equal record.type_for_attribute('name_length').type, definitions.last[:cast_type]
  end

  test 'a record is described without consulting the ACL' do
    create(:property)
    controller = PropertiesController.new
    controller.expects(:model_attributes).never

    schemas(Property.last, controller: controller)
  end

end
