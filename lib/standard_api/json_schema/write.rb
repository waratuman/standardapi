module StandardAPI
  module JSONSchema
    # The shape of the params #create and #update accept, served at
    # schema/write
    module Write

      # The shape of the params #create and #update accept for +model+: the
      # attributes the ACL's +attributes+ permit, and the associations its
      # +nested+ permits. +required+ lists what a create needs; an update needs
      # none of it.
      def write_schema_for(model)
        schema = model_write_schema(model, [])
        if schema['required']
          schema['$comment'] = 'required applies to a create. An update may send any of the properties.'
        end

        {
          '$schema' => DIALECT,
          'title' => model.model_name.human,
          'description' => model_description(model),
          'type' => 'object',
          'properties' => { model_name(model) => schema }
        }.compact
      end

      private

      # +path+ holds the models already being described, so an association
      # nested back into one of them isn't described again.
      def model_write_schema(model, path, nested: false)
        if self.respond_to?("filter_#{model_name(model)}_params", true)
          return {
            'type' => 'object',
            'description' => "Filtered by #{model.name}ACL#filter"
          }
        end

        properties = {}
        required = []
        properties['id'] = attribute_write_schema(model, model.primary_key) if nested && model.primary_key
        definitions = definitions_for(model)

        Array(model_attributes(model)).flatten.each do |entry|
          if entry.is_a?(Hash)
            entry.each do |name, permit|
              properties[name.to_s] = permit == [] ? { 'type' => 'array' } : { 'type' => 'object' }
            end
          else
            name = entry.to_s
            properties[name] = attribute_write_schema(model, name)
            required << name if !nested && definitions.dig(name, :required)
          end
        end

        properties.merge!(nested_write_schemas(model, path + [model]))

        {
          'type' => 'object',
          'properties' => properties,
          'additionalProperties' => false,
          'required' => (required if required.any?)
        }.compact
      end

      # The JSON Schema of the attribute +name+ from its definition, with its
      # validations, or {} if the Schema doesn't declare it. It's readOnly
      # when the definition is read only: an attr_readonly attribute, which
      # can be set on create but not changed, or one the Schema says is.
      def attribute_write_schema(model, name)
        definition = definitions_for(model)[name.to_s]
        return {} if !definition

        schema = definition_value_schema(model, definition, validations: true)
        schema = { 'type' => 'array', 'items' => schema } if definition[:array]
        # Only a NOT NULL column can't be null
        schema = nullable(schema) if definition[:null] != false

        # For an array these describe the array, not its items
        schema['readOnly'] = true if definition[:read_only]
        schema['default'] = definition[:default] if !definition[:default].nil?
        schema['description'] = definition[:comment] if definition[:comment]
        schema
      end

      # Mirrors AccessControlList#filter_model_params
      def nested_write_schemas(model, path)
        method = "nested_#{model_name(model)}_attributes"
        return {} if !self.respond_to?(method, true)

        self.send(method).each_with_object({}) do |relation, schemas|
          association = model.reflect_on_association(relation)
          next if !association

          if association.belongs_to?
            schemas[association.foreign_key.to_s] = attribute_write_schema(model, association.foreign_key.to_s)
            schemas[association.foreign_type.to_s] = { 'type' => 'string' } if association.polymorphic?
          end
          next if association.polymorphic?

          record = if path.include?(association.klass)
            { 'type' => 'object' }
          else
            model_write_schema(association.klass, path, nested: true)
          end

          schemas[association.name.to_s] = if association.collection?
            schemas["#{association.name.to_s.singularize}_ids"] = { 'type' => 'array', 'items' => id_schema(association) }
            { 'type' => ['array', 'null'], 'items' => record }
          else
            nullable(record)
          end
        end
      end

      # Of a collection, which is never polymorphic
      def id_schema(association)
        definition = definitions_for(association.klass)[association.klass.primary_key]
        definition ? definition_value_schema(association.klass, definition) : {}
      end

    end
  end
end
