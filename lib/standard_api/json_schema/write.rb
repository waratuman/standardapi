module StandardAPI
  module JSONSchema
    # Values for schema/write (application/json_schema/_write)
    module Write

      private

      # The attributes the ACL's +attributes+ permit for +model+: names, and
      # Hashes of a name to its permitted Array ([]) or Hash
      def json_schema_attributes(model)
        Array(model_attributes(model)).flatten
      end

      # The associations the ACL's +nested+ permits for +model+, as
      # AccessControlList#filter_model_params reads them
      def json_schema_nested(model)
        method = "nested_#{model_name(model)}_attributes"
        return [] if !self.respond_to?(method, true)

        self.send(method).filter_map { |relation| model.reflect_on_association(relation) }
      end

      # Whether the ACL's +filter+ filters the params of +model+, so they
      # aren't described
      def json_schema_filtered?(model)
        self.respond_to?("filter_#{model_name(model)}_params", true)
      end

      # The JSON Schema of the attribute +name+ from its definition, with its
      # validations, or {} if the Schema doesn't declare it. It's readOnly
      # when the definition is read only: an attr_readonly attribute, which
      # can be set on create but not changed, or one the Schema says is.
      def json_schema_attribute_write(model, name)
        definition = json_schema_definitions(model)[name.to_s]
        return {} if !definition

        schema = definition_value_schema(model, definition, validations: true)
        schema = { 'type' => 'array', 'items' => schema } if definition[:array]
        # Only a NOT NULL column can't be null
        schema = json_schema_nullable(schema) if definition[:null] != false

        # For an array these describe the array, not its items
        schema['readOnly'] = true if definition[:read_only]
        schema['default'] = definition[:default] if !definition[:default].nil?
        schema['description'] = definition[:comment] if definition[:comment]
        schema
      end

      # The JSON Schema of an id of a record of +association+
      def json_schema_id(association)
        return {} if association.polymorphic?

        definition = json_schema_definitions(association.klass)[association.klass.primary_key]
        definition ? definition_value_schema(association.klass, definition) : {}
      end

    end
  end
end
