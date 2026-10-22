required = Set.new
json.set! '$schema', local_assigns[:schema] if local_assigns[:schema]
json.set! 'title', model.table_name.titleize.singularize
# A singular association rendered as an include may be absent
json.set! 'type', local_assigns[:nullable] ? ['object', 'null'] : 'object'
if comment = model.connection.table_comment(model.table_name)
  json.set! 'description', comment
end
# The attributes the ACL lets a client write; any other is read only
permitted = controller.model_attributes(model)&.map(&:to_s)
# What the ACL excludes from a new record, as application/_record does
excluded = resolve_excludes(model.new, local_assigns[:excludes])
json.set! 'properties' do
  schemas_for(model).each do |schema|
    name = schema.fetch(:name)
    next if includes["only"]&.exclude?(name)
    next if includes["except"]&.include?(name)
    next if excluded[name] == true
    schema_properties = json_schema_for_type(schema.fetch(:type))

    required.add(name) if schema[:required]

    schema[:validations]&.each do |v|
      options = v[:options]
      case v[:kind]
      when :numericality
        schema_properties["exclusiveMinimum"] = options[:greater_than] if options[:greater_than]
        schema_properties["exclusiveMaximum"] = options[:less_than] if options[:less_than]
        schema_properties["minimum"] = options[:greater_than_or_equal_to] if options[:greater_than_or_equal_to]
        schema_properties["maximum"] = options[:less_than_or_equal_to] if options[:less_than_or_equal_to]
      when :inclusion
        case options[:in]
        when Array
          schema_properties["enum"] = options[:in]
        when Range
          # A Range of numbers bounds the value; JSON Schema can't describe others
          range = options[:in]
          if [range.begin, range.end].compact.all?(Numeric)
            schema_properties["minimum"] = range.begin if range.begin
            schema_properties[range.exclude_end? ? "exclusiveMaximum" : "maximum"] = range.end if range.end
          end
        end
      when :acceptance
        schema_properties["const"] = true
      when :format
        # JSON Schema patterns are ECMA 262, so only a Regexp JavaScript reads the
        # same way: no flags, inline flag groups like (?i), \A, \z, \Z, \G or \h
        with = options[:with]
        if with.is_a?(Regexp) && with.options == 0 && with.source !~ /\\[AzZGh]|\(\?[imx-]+[:)]/
          schema_properties["pattern"] = with.source
        elsif with.is_a?(Regexp)
          Rails.logger.warn("#{model.name}##{name} format #{with.inspect} isn't an ECMA 262 pattern, so it's left out of the JSON Schema")
        end
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

    # Rails enums are described by their names
    schema_properties["enum"] = schema[:enum] if schema[:enum]
    # A column that allows NULL renders null, as does a definition that
    # doesn't say
    if schema.fetch(:null, true) && !schema[:array]
      schema_properties[:type] = Array(schema_properties[:type]) + ['null'] if schema_properties[:type]
      schema_properties["enum"] += [nil] if schema_properties["enum"]
    end

    json.set! name do
      if schema[:array]
        json.set! 'type', schema.fetch(:null, true) ? ['array', 'null'] : 'array'
        json.set! 'items', schema_properties
      else
        json.merge! schema_properties
      end
      # For an array these describe the array, not its items
      json.set! 'readOnly', true if (permitted && permitted.exclude?(name)) || model.readonly_attribute?(name)
      json.set! 'default', schema[:default] if !schema[:default].nil?
      json.set! 'description', schema[:comment] if schema[:comment]
    end
  end
  includes.each do |inc, subinc|
    next if %w(only except).include?(inc)
    next if includes["only"]&.exclude?(inc)
    next if includes["except"]&.include?(inc)
    next if excluded[inc] == true
    case association = model.reflect_on_association(inc)
    when ::ActiveRecord::Reflection::AbstractReflection
      json.set! inc do
        if association.collection?
          json.set! 'type', 'array'
          json.set! 'items' do
            json.partial!('json_schema', model: association.klass, includes: subinc, excludes: sub_excludes(excluded, inc))
          end
        else
          # A required belongs_to (or a has_one validated for presence) has a
          # presence validation; any other may be absent
          json.partial!('json_schema', model: association.klass, includes: subinc, excludes: sub_excludes(excluded, inc),
            nullable: model.validators_on(association.name).none? { |v| v.kind == :presence })
        end
      end
    end
  end
end
json.set! 'required', required.to_a