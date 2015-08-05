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
    if defined?(model_class_name.constantize)
      model_class = model_class_name.constantize
      klass.send(:filters=, model_class.attribute_names)
      klass.send(:orders=, model_class.attribute_names)
      klass.send(:includes=, model_class.reflect_on_all_associations.map(&:name))
    end
    
    klass.extend(ClassMethods)

    klass.controller_class.action_methods.each do |action|
      if const_defined?("StandardAPI::TestCase::#{action.capitalize}Tests")
        # Include the test if there is a route
        # if Rails.application.routes.url_for(controller: @controller.controller_path, action: 'destroy', only_path: true)

        klass.include("StandardAPI::TestCase::#{action.capitalize}Tests".constantize)
      end
    end
  end

  def model
    self.class.model
  end

  def create_model(attrs={})
    create(model.name.underscore, attrs)
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
    
  def normalize_attribute(attribute, value)
    validators = self.class.model.validators_on(attribute)
    value
  end
    
  def normalize_to_json(attribute, value)
    value = normalize_attribute(attribute, value)
      
    return nil if value.nil?

    if model.column_types[attribute].is_a?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Decimal)
      "#{value}"
    elsif model.column_types[attribute].is_a?(ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter)
      value.to_datetime.utc.iso8601.gsub(/\+00:00$/, 'Z')
    else
      value
    end
  end

  module ClassMethods
    
    def include_filter_tests
      model.instance_variable_get('@filters').each do |filter|
        next if filter[1].is_a?(Proc) # Custom filter
        next if model.reflect_on_association(filter[0]) # TODO: Relation Filter Tests

        define_method("test_model_filter_#{filter[0]}") do
          m = create_model
          value = m.send(filter[0])

          assert_predicate = -> (predicate) {
            get :index, where: predicate, format: 'json'
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

  end

end
