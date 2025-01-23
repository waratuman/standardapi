require 'active_support/test_case'

require File.expand_path(File.join(__FILE__, '../test_case/calculate_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/create_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/destroy_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/index_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/new_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/schema_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/show_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/update_tests'))

module StandardAPI::TestCase

  def assert_equal_or_nil(expected, *args)
    if expected.nil?
      assert_nil(*args)
    else
      assert_equal(expected, *args)
    end
  end

  def self.included(klass)
    [:filters, :orders, :includes].each do |attribute|
      klass.send(:class_attribute, attribute)
    end

    begin
      model_class = klass.name.gsub(/Test$/, '').constantize.model

      klass.send(:filters=, model_class.attribute_names)
      klass.send(:orders=, model_class.attribute_names)
      klass.send(:includes=, model_class.reflect_on_all_associations.map(&:name))
    rescue NameError => e
      raise e if e.message != "uninitialized constant #{model_class_name}"
    end

    klass.extend(ClassMethods)

    routes = Rails.application.routes.set.routes.inject({}) do |acc, r|
      acc[r.defaults[:controller]] ||= {}
      acc[r.defaults[:controller]][r.defaults[:action]] = true
      acc
    end

    test_cases = Dir.entries(File.expand_path(File.join(__FILE__, '..', 'test_case')))
    test_cases.select! {|fn| fn.ends_with?('_tests.rb') }
    test_cases.map! {|fn| fn.sub('_tests.rb', '') }
    (klass.controller_class.action_methods & test_cases).each do |action|
      if const_defined?("StandardAPI::TestCase::#{action.capitalize}Tests") && routes[klass.controller_class.controller_path][action]
        klass.include("StandardAPI::TestCase::#{action.capitalize}Tests".constantize)
      end
    end
  end

  def supports_format(format, action=nil)
    count = controller_class.view_paths.count do |path|
      !Dir.glob("#{path.instance_variable_get(:@path)}/{#{model.name.underscore},application}/**/#{action || '*'}.#{format}*").empty?
    end

    count > 0
  end

  def default_orders
    controller_class.new.send(:default_orders)
  end

  def resource_limit
    controller_class.new.send(:resource_limit)
  end

  def default_limit
    controller_class.new.send(:default_limit)
  end

  def model
    self.class.model
  end

  def mask
    {}
  end

  def resource_path(action, options={})
    url_for({
      controller: controller_class.controller_path, action: action
    }.merge(options))
  end

  def controller_class
    self.class.controller_class
  end

  def create_model(attrs={})
    create(model.name.underscore, attrs.merge(mask))
  end

  def singular_name
    model.model_name.singular
  end

  def plural_name
    model.model_name.plural
  end

  def create_webmocks(attributes)
    attributes.each do |attribute, value|
      self.class.model.validators_on(attribute)
    end
  end

  def normalizers
    self.class.instance_variable_get('@normalizers')
  end

  def normalize_attribute(record, attribute, value)
    if normalizers[self.class.model] && normalizers[self.class.model][attribute]
      b = normalizers[self.class.model][attribute]
      b.arity == 2 ? b.call(record, value) : b.call(value)
    else
      # validators = self.class.model.validators_on(attribute)
      value
    end
  end

  def normalize_to_json(record, attribute, value)
    value = normalize_attribute(record, attribute, value)
    return nil if value.nil?

    if model.columns_hash[attribute].is_a?(::ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Decimal)
      "#{value.to_f}"
    elsif value.is_a?(DateTime) #model.columns_hash[attribute].is_a?(ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter)
      value.in_time_zone.as_json
    else
      value.as_json
    end
  end

  def view_attributes(record)
    return [] if record.nil?
    record.attributes.select do |x|
      !@controller.send(:excludes_for, record.class).include?(x.to_sym)
    end
  end

  def update_attributes(record)
    return [] if record.nil?
    record.attributes.select do |x|
      !record.class.readonly_attributes.include?(x.to_s) &&
      !@controller.send(:excludes_for, record.class).include?(x.to_sym)
    end
  end
  alias_method :create_attributes, :update_attributes

  module ClassMethods

    def self.extended(klass)
      klass.instance_variable_set('@normalizers', {})
    end

    def controller_class
      controller_class_name = self.name.gsub(/Test$/, '')
      controller_class_name.constantize
    rescue NameError => e
      raise e if e.message != "uninitialized constant #{controller_class_name}"
    end

    def model=(val)
      @model = val
      self.filters = val.attribute_names
      self.orders = val.attribute_names
      self.includes = val.reflect_on_all_associations.map(&:name)
      @model
    end

    def model
      return @model if defined?(@model) && @model

      klass_name = controller_class.name.gsub(/Controller$/, '').singularize

      begin
        @model = klass_name.constantize
      rescue NameError
        raise e unless e.message =~ /uninitialized constant #{klass_name}/
      end

      if @model.nil?
        raise "@model is nil: make sure you set it in your test using `self.model = ModelClass`."
      else
        @model
      end
    end

    def normalize(*attributes, &block)
      attributes.each do |attribute|
        @normalizers[model] ||= {}
        @normalizers[model][attribute] = block
      end
    end

  end

end
