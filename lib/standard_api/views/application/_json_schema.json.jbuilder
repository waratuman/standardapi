required = Set.new
json.set! 'title', model.table_name.titleize.singularize
json.set! 'type', 'object'
if comment = model.connection.table_comment(model.table_name)
  json.set! 'description', comment
end
json.set! 'properties' do
  model.columns.each do |column|
    next if includes["only"]&.exclude?(column.name)
    next if includes["except"]&.include?(column.name)
    column_schema = json_column_schema(column.sql_type)
    
    if controller.respond_to?("#{ model.model_name.singular }_attributes") && controller.send("#{ model.model_name.singular }_attributes").map(&:to_s).exclude?(column.name)
      column_schema[:readOnly] = true
    elsif column.respond_to?(:auto_populated?) && !!column.auto_populated?
      column_schema[:readOnly] = true
    end
    
    if default = column.default ? model.connection.lookup_cast_type_from_column(column).deserialize(column.default) : nil
      column_schema[:default] = default
    end
    
    if column.comment
      column_schema[:description] = column.comment
    end
    
    if column.null == false && column_schema[:readOnly] != true
      required.add(column.name)
    end
    
    if model.type_for_attribute(column.name).is_a?(::ActiveRecord::Enum::EnumType)
      column_schema[:default] = model.defined_enums[column.name].key(default)
      column_schema[:type] = 'string'
    end

    model.validators.select { |v| v.attributes.include?(column.name.to_sym) }.each do |v|
      case v
      when ::ActiveRecord::Validations::NumericalityValidator
        column_schema["exclusiveMinimum"] = v.options[:greater_than] if v.options[:greater_than]
        column_schema["exclusiveMaximum"] = v.options[:less_than] if v.options[:less_than]
        column_schema["minimum"] = v.options[:greater_than_or_equal_to] if v.options[:greater_than_or_equal_to]
        column_schema["maximum"] = v.options[:less_than_or_equal_to] if v.options[:less_than_or_equal_to]
      when ::ActiveModel::Validations::InclusionValidator
        column_schema["enum"] = v.options[:in] if v.options[:in]
      when ::ActiveModel::Validations::AcceptanceValidator
        column_schema["const"] = true
        required.add(column.name) if v.options[:allow_nil] != true
      when ::ActiveModel::Validations::FormatValidator
        column_schema["pattern"] = v.options[:with] if v.options[:with]
      when ::ActiveModel::Validations::LengthValidator
        column_schema["minLength"] = v.options[:minimum] if v.options[:minimum]
        column_schema["maxLength"] = v.options[:maximum] if v.options[:maximum]
      when ::ActiveModel::Validations::PresenceValidator
        required.add(column.name)
      else
        puts "******* MISSING VALIDATOR **********"
        puts v.inspect
        warn "missing validator"
      end
    end

    json.set! column.name do
      if column.array
        json.set! 'type', 'array'
        json.set! 'items', column_schema
      else
        json.merge! column_schema
      end
    end
  end
  includes.each do |inc, subinc|
    next if %w(only except).include?(inc)
    next if includes["only"]&.exclude?(inc)
    next if includes["except"]&.include?(inc)
    case association = model.reflect_on_association(inc)
    when ::ActiveRecord::Reflection::AbstractReflection
      json.set! inc do
        if association.collection?
          json.set! 'type', 'array'
          json.set! 'items' do
            json.partial!('json_schema', model: association.klass, includes: subinc)
          end
        else
          json.partial!('json_schema', model: association.klass, includes: subinc)
        end
      end
    end
  end
end
json.set! 'required', required.to_a