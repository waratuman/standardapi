required = Set.new
json.set! 'title', model.table_name.titleize.singularize
json.set! 'type', 'object'
if comment = model.connection.table_comment(model.table_name)
  json.set! 'description', comment
end
json.set! 'properties' do
  schemas_for(model).each do |schema|
    name = schema[:name]
    next if includes["only"]&.exclude?(name)
    next if includes["except"]&.include?(name)
    schema_properties = json_schema_for_type(schema[:type])

    schema_properties[:readOnly] = true if schema[:read_only] || schema[:auto_populated]
    schema_properties[:default] = schema[:default] if !schema[:default].nil?
    schema_properties[:description] = schema[:comment] if schema[:comment]
    required.add(name) if schema[:required]

    schema[:validations].each do |v|
      options = v[:options]
      case v[:kind]
      when :numericality
        schema_properties["exclusiveMinimum"] = options[:greater_than] if options[:greater_than]
        schema_properties["exclusiveMaximum"] = options[:less_than] if options[:less_than]
        schema_properties["minimum"] = options[:greater_than_or_equal_to] if options[:greater_than_or_equal_to]
        schema_properties["maximum"] = options[:less_than_or_equal_to] if options[:less_than_or_equal_to]
      when :inclusion
        schema_properties["enum"] = options[:in] if options[:in]
      when :acceptance
        schema_properties["const"] = true
      when :format
        schema_properties["pattern"] = options[:with] if options[:with]
      when :length
        schema_properties["minLength"] = options[:minimum] if options[:minimum]
        schema_properties["maxLength"] = options[:maximum] if options[:maximum]
      when :presence
        # Already counted in schema[:required]
      else
        puts "******* MISSING VALIDATOR **********"
        puts v.inspect
        warn "missing validator"
      end
    end

    json.set! name do
      if schema[:array]
        json.set! 'type', 'array'
        json.set! 'items', schema_properties
      else
        json.merge! schema_properties
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