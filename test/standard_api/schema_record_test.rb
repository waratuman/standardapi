require 'standard_api/test_helper'

class SchemaRecordTest < ActiveSupport::TestCase

  def controller
    @controller ||= PropertiesController.new
  end

  def with_account_schema(schema)
    schemas = ApplicationController.standard_api_schemas.merge('account' => schema)
    ApplicationController.stubs(:standard_api_schemas).returns(schemas)
    yield
  ensure
    ApplicationController.unstub(:standard_api_schemas)
  end

  test 'attributes are what the Schema declares, less what a narrowing Schema hides' do
    account = create(:account)
    narrow = Class.new(StandardAPI::Schema) { attributes :id, :name }

    assert_includes controller.schema_for(account).attributes.map { |d| d[:name] }, 'email'
    schema = controller.schema_for(account, [narrow])
    assert_equal %w[id name], schema.attributes.map { |d| d[:name] }.sort
    assert schema.attribute?(:name)
    assert_not schema.attribute?(:email)
  end

  test 'include? is false for an association a Schema hides, and true for a method' do
    account = create(:account)
    narrow = Class.new(StandardAPI::Schema) { associations :photos }

    with_account_schema(Class.new(AccountSchema) { remove :property }) do
      schema = controller.schema_for(account)
      assert_not schema.include?(:property)
      assert schema.include?(:photos)
      assert schema.include?(:not_an_association)
      assert_not controller.schema_for(account, [narrow]).include?(:subject)
    end
  end

  test 'narrowing_for gives the Schemas an association narrows its records with' do
    narrow = Class.new(StandardAPI::Schema) { attributes :id }
    with_account_schema(Class.new(AccountSchema) { association :photos, schema: narrow }) do
      schema = controller.schema_for(create(:account))
      assert_equal [narrow], schema.narrowing_for(:photos)
      assert_equal [], schema.narrowing_for(:property)
    end
  end

  test 'hidden? is false for a name that is neither an attribute nor an association' do
    assert_not controller.schema_for(create(:account)).hidden?(:not_an_attribute)
  end

  test 'errors leave out those on what it hides' do
    account = build(:account)
    account.errors.add(:email, 'is taken by someone@example.com')
    account.errors.add(:name, 'is blank')
    account.errors.add(:base, 'is wrong')

    with_account_schema(Class.new(AccountSchema) { remove :email }) do
      assert_equal %w[base name], controller.schema_for(account).errors.keys.map(&:to_s).sort
    end
  end

end
