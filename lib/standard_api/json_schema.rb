require 'standard_api/json_schema/read'
require 'standard_api/json_schema/write'
require 'standard_api/json_schema/query'

module StandardAPI
  # Included in StandardAPI::Controller. Builds the JSON Schemas served at
  # schema/read, schema/write and schema/query, each from the ACL, so it only
  # describes what the ACL permits. Attributes are described from their
  # definitions in schemas_for(model), so only what the model's Schema
  # declares. Params the ACL doesn't check yet are described as they're used,
  # and say so.
  #
  # read_schema_for, write_schema_for and query_schema_for are public, like
  # schemas_for, so a caller can build a schema on a controller bound to a
  # request and validate in-process, without dispatching the action.
  module JSONSchema

    DIALECT = 'https://json-schema.org/draft/2020-12/schema'.freeze

    include Read
    include Write
    include Query

    private

    def model_description(model)
      model.connection.table_comment(model.table_name)
    end

    # schemas_for(model), as name => definition
    def definitions_for(model)
      @definitions_for ||= {}
      @definitions_for[model] ||= schemas_for(model).index_by { |definition| definition[:name].to_s }
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
    #
    # Only what JSON Schema can state is: a validation that doesn't always
    # run (+if+, +unless+, +on+) or that passes a blank value (+allow_blank+)
    # is left out, as is an option given as a Symbol or a Proc, so the schema
    # never rejects what the model accepts.
    def apply_validations(schema, model, definition)
      Array(definition[:validations]).each do |v|
        options = v[:options]
        next if options[:if] || options[:unless] || options[:on] || options[:allow_blank]

        case v[:kind]
        when :numericality
          {
            greater_than: 'exclusiveMinimum',
            less_than: 'exclusiveMaximum',
            greater_than_or_equal_to: 'minimum',
            less_than_or_equal_to: 'maximum'
          }.each do |option, keyword|
            schema[keyword] = options[option] if options[option].is_a?(Numeric)
          end
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
          # Accepts nil unless told not to
          if options[:allow_nil] == false
            schema['const'] = true
          else
            schema['enum'] = [true, nil]
          end
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
          schema['minLength'] = options[:minimum] if options[:minimum].is_a?(Integer)
          schema['maxLength'] = options[:maximum] if options[:maximum].is_a?(Integer)
        when :presence
          # Already counted in the definition's +required+
        else
          Rails.logger.debug("#{model.name}##{definition[:name]} #{v[:kind]} validation has no JSON Schema equivalent, so it's left out")
        end
      end
    end

    def nullable(schema)
      schema = schema.dup
      schema['enum'] |= [nil] if schema['enum']

      case schema['type']
      when String then schema['type'] = [schema['type'], 'null']
      when Array then schema['type'] = schema['type'] | ['null']
      end
      schema
    end

  end
end
