require 'active_support/test_case'

require File.expand_path(File.join(__FILE__, '../test_case/calculate_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/create_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/destroy_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/index_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/show_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/update_tests'))

module StandardAPI::TestCase
      
  def self.included(klass)
    model_class_name = klass.controller_class.name.gsub(/Controller$/, '').singularize

    [:filters, :orders, :includes].each do |attribute|
      klass.send(:class_attribute, attribute)
    end

    begin
      model_class = model_class_name.constantize
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

    klass.controller_class.action_methods.each do |action|
      if const_defined?("StandardAPI::TestCase::#{action.capitalize}Tests") && routes[klass.controller_class.controller_path][action]
        klass.include("StandardAPI::TestCase::#{action.capitalize}Tests".constantize)
      end
    end
  end

  def model
    self.class.model
  end

  def create_model(*args)
    create(model.name.underscore, *args)
  end

  def singular_name
    model.model_name.singular
  end
  
  def plural_name
    model.model_name.plural
  end
    
  def create_webmocks(attributes)
    attributes.each do |attribute, value|
      validators = self.class.model.validators_on(attribute)
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

    if model.columns_hash[attribute].is_a?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Decimal)
      "#{value.to_f}"
    elsif value.is_a?(DateTime) #model.columns_hash[attribute].is_a?(ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter)
      value.in_time_zone.as_json
    else
      value.as_json
    end
  end

  def view_attributes(record)
    return [] if record.nil?
    record.attributes.select { |x| !@controller.send(:excludes_for, record.class).include?(x.to_sym) }
  end

  module ClassMethods

    def self.extended(klass)
      klass.instance_variable_set('@normalizers', {})
    end

    def include_filter_tests
      model.instance_variable_get('@filters').each do |filter|
        next if filter[1].is_a?(Proc) # Custom filter
        next if model.reflect_on_association(filter[0]) # TODO: Relation Filter Tests

        define_method("test_model_filter_#{filter[0]}") do
          m = create_model
          value = m.send(filter[0])

          assert_predicate = -> (predicate) {
            get :index, params: {where: predicate}, format: 'json'
            assert_equal model.filter(predicate).to_sql, assigns(plural_name).to_sql
          }

          # TODO: Test array
          case model.columns_hash[filter[0].to_s].type
          when :jsonb, :json # JSON
            assert_predicate.call({ filter[0] => value })
          else
            case value
            when Array
              assert_predicate.call({ filter[0] => value }) # Overlaps
              assert_predicate.call({ filter[0] => value[0] }) # Contains
            else
              assert_predicate.call({ filter[0] => value }) # Equality
              assert_predicate.call({ filter[0] => { gt: value } }) # Greater Than
              assert_predicate.call({ filter[0] => { greater_than: value } })
              assert_predicate.call({ filter[0] => { lt: value } }) # Less Than
              assert_predicate.call({ filter[0] => { less_than: value } })
              assert_predicate.call({ filter[0] => { gte: value } }) # Greater Than or Equal To
              assert_predicate.call({ filter[0] => { gteq: value } })
              assert_predicate.call({ filter[0] => { greater_than_or_equal_to: value } })
              assert_predicate.call({ filter[0] => { lte: value } }) # Less Than or Equal To
              assert_predicate.call({ filter[0] => { lteq: value } })
              assert_predicate.call({ filter[0] => { less_than_or_equal_to: value } })
            end
          end
        end
      end
    end

    def model=(val)
      @model = val
      filters = val.attribute_names
      orders = val.attribute_names
      includes = val.reflect_on_all_associations.map(&:name)
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
