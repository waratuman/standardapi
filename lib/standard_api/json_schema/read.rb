module StandardAPI
  module JSONSchema
    # Values for schema/read (application/json_schema/_read)
    module Read

      private

      # The JSON Schema of the attribute a definition describes, as
      # application/_record serializes it. Validations aren't applied: a record
      # saved before one was added may not pass it.
      def json_schema_attribute_read(model, definition)
        schema = case definition[:type]
        when 'binary'
          # Serialized as hex
          { 'type' => 'string', 'contentEncoding' => 'base16' }
        when 'decimal', 'money'
          # A BigDecimal renders as a String
          { 'type' => 'string' }
        else
          definition_value_schema(model, definition)
        end

        schema = { 'type' => 'array', 'items' => schema } if definition[:array]
        # Only a NOT NULL column can't be null
        schema = json_schema_nullable(schema) if definition[:null] != false
        schema['description'] = definition[:comment] if definition[:comment]
        schema
      end

    end
  end
end
