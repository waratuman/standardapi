module StandardAPI
  module JSONSchema
    # The shape of a record as #show renders it, served at schema/read
    module Read

      # The shape #show renders for +model+ with +includes+, ie. each record
      # #index renders. +includes+ are normalized and checked against the ACL,
      # as Controller#includes gives them.
      def read_schema_for(model, includes)
        {
          '$schema' => DIALECT,
          'title' => model.model_name.human
        }.merge(record_read_schema(model, includes))
      end

      private

      def record_read_schema(model, includes)
        if model_partial(model) != 'application/record'
          return {
            'type' => 'object',
            'description' => "Rendered by #{model_partial(model)}"
          }
        end

        properties = definitions_for(model).transform_values do |definition|
          attribute_read_schema(model, definition)
        end
        # Columns are always rendered. Other attributes may not be loaded, ie.
        # under a partial select, or may be ones the Schema adds.
        required = properties.keys & model.column_names

        includes.each do |name, subincludes|
          next if StandardAPI::Controller::RESERVED_INCLUDE_KEYS.include?(name.to_s)

          association = model.reflect_on_association(name)
          # #index only renders an include with a +when+ for the records that
          # match it
          required << name.to_s if !subincludes.respond_to?(:key?) || !subincludes.key?('when')
          properties[name.to_s] = if !association
            {}
          elsif association.polymorphic?
            { 'type' => ['object', 'null'] }
          elsif association.collection?
            { 'type' => 'array', 'items' => record_read_schema(association.klass, subincludes) }
          elsif model.validators_on(association.name).any? { |v| v.kind == :presence }
            # A required belongs_to (or a has_one validated for presence)
            record_read_schema(association.klass, subincludes)
          else
            nullable(record_read_schema(association.klass, subincludes))
          end
        end

        # An ACL exclude or a Schema condition can leave out any of them. What
        # they hide is still described, as some records render it.
        required = [] if excludes?(model)

        properties['errors'] = {
          'type' => 'object',
          'description' => 'Validation errors, when a create or update fails',
          'additionalProperties' => { 'type' => 'array', 'items' => { 'type' => 'string' } }
        }

        {
          'description' => model_description(model),
          'type' => 'object',
          'properties' => properties,
          'additionalProperties' => false,
          'required' => (required if required.any?)
        }.compact
      end

      # The JSON Schema of the attribute a definition describes, as
      # application/_record serializes it. Validations aren't applied: a record
      # saved before one was added may not pass it.
      def attribute_read_schema(model, definition)
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
        schema = nullable(schema) if definition[:null] != false
        schema['description'] = definition[:comment] if definition[:comment]
        schema
      end

    end
  end
end
