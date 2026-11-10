module StandardAPI
  # Included in StandardAPI::Controller. The helpers the schema/read,
  # schema/write and schema/query views (application/read_schema,
  # write_schema and query_schema, and the application/json_schema partials)
  # are built with.
  #
  # The views lay out each JSON Schema: its objects, properties, required and
  # the records and associations they recurse into. These describe the values
  # in it, ie. an attribute from its definition in schemas_for(model), and
  # read the ACL for the views, so each schema only describes what the ACL
  # permits.
  module JSONSchema

    DIALECT = 'https://json-schema.org/draft/2020-12/schema'.freeze

    # The methods the views call
    HELPERS = %i(
      json_schema_definitions json_schema_description json_schema_nullable
      json_schema_attribute_read json_schema_attribute_write json_schema_id
      json_schema_attributes json_schema_nested json_schema_filtered?
      json_schema_wheres json_schema_orders json_schema_includes
      json_schema_required_orders json_schema_name json_schema_ref
      json_schema_column_where json_schema_direction json_schema_columns
      json_schema_select json_schema_unchecked json_schema_param_key
    ).freeze

  end
end

require 'standard_api/json_schema/read'
require 'standard_api/json_schema/write'
require 'standard_api/json_schema/query'

module StandardAPI
  module JSONSchema
    include Read
    include Write
    include Query

    private

    # The key #create and #update read +model+'s params from
    def json_schema_param_key(model)
      model_name(model)
    end

    def json_schema_description(model)
      model.connection.table_comment(model.table_name)
    end

    # schemas_for(model), as name => definition
    def json_schema_definitions(model)
      @json_schema_definitions ||= {}
      @json_schema_definitions[model] ||= schemas_for(model).index_by { |definition| definition[:name].to_s }
    end

    # The JSON Schema of a value of the attribute a definition describes, from
    # its +type+ (Helpers#json_schema_for_type) and +enum+, and with
    # +validations+ its validations. Not nullable: the caller decides.
    def definition_value_schema(model, definition, validations: false)
      schema = helpers.json_schema_for_type(definition[:type]).deep_stringify_keys
      apply_validations(schema, model, definition) if validations
      # Rails enums are described by their names
      schema['enum'] = definition[:enum] if definition[:enum]
      schema
    end

    # The validations of a definition, as JSON Schema. A presence validation
    # is in the definition's +required+.
    def apply_validations(schema, model, definition)
      Array(definition[:validations]).each do |v|
        options = v[:options]
        case v[:kind]
        when :numericality
          schema['exclusiveMinimum'] = options[:greater_than] if options[:greater_than]
          schema['exclusiveMaximum'] = options[:less_than] if options[:less_than]
          schema['minimum'] = options[:greater_than_or_equal_to] if options[:greater_than_or_equal_to]
          schema['maximum'] = options[:less_than_or_equal_to] if options[:less_than_or_equal_to]
        when :inclusion
          case options[:in]
          when Array
            schema['enum'] = options[:in]
          when Range
            # A Range of numbers bounds the value; JSON Schema can't describe others
            range = options[:in]
            if [range.begin, range.end].compact.all?(Numeric)
              schema['minimum'] = range.begin if range.begin
              schema[range.exclude_end? ? 'exclusiveMaximum' : 'maximum'] = range.end if range.end
            end
          end
        when :acceptance
          schema['const'] = true
        when :format
          # JSON Schema patterns are ECMA 262, so only a Regexp JavaScript reads
          # the same way: no flags, inline flag groups like (?i), \A, \z, \Z, \G
          # or \h
          with = options[:with]
          if with.is_a?(Regexp) && with.options == 0 && with.source !~ /\\[AzZGh]|\(\?[imx-]+[:)]/
            schema['pattern'] = with.source
          elsif with.is_a?(Regexp)
            Rails.logger.warn("#{model.name}##{definition[:name]} format #{with.inspect} isn't an ECMA 262 pattern, so it's left out of the JSON Schema")
          end
        when :length
          schema['minLength'] = options[:minimum] if options[:minimum]
          schema['maxLength'] = options[:maximum] if options[:maximum]
        when :presence
          # Already counted in the definition's +required+
        else
          Rails.logger.debug("#{model.name}##{definition[:name]} #{v[:kind]} validation has no JSON Schema equivalent, so it's left out")
        end
      end
    end

    # +schema+, or its +type+ when given a type, allowing null
    def json_schema_nullable(schema)
      return [schema, 'null'] if schema.is_a?(String)

      schema = schema.dup
      if schema['enum']
        schema['enum'] = schema['enum'] + [nil]
      end

      case schema['type']
      when String then schema['type'] = [schema['type'], 'null']
      when Array then schema['type'] = schema['type'] | ['null']
      end
      schema
    end

  end
end
