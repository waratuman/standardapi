# Mirrors StandardAPI::Wheres#check_wheres: a Hash of the keys the ACL's
# wheres permit on +model+, or an Array of them joined by "AND" and "OR". A
# bare value is checked as an `eq` on id, but isn't presented:
# activerecord-filter can't filter on one from a query string.
json.set! 'anyOf' do
  json.child! do
    pattern_properties = {}

    json.set! 'type', 'object'
    json.set! 'properties' do
      # Jbuilder leaves out a block that sets nothing
      json.merge!({})
      json_schema_wheres(model).each do |key, operators|
        if model.filters.has_key?(key)
          json.set! key, { 'description' => "The #{key} filter" }
        elsif column = model.columns_hash[key]
          schema = json_schema_column_where(model, column, operators)
          json.set! key, schema
          if [:json, :jsonb].include?(column.type)
            pattern_properties["^#{Regexp.escape(key)}\\..+$"] = schema
          end
        elsif association = model.reflect_on_association(key)
          exists = if association.belongs_to?
            { 'type' => ['boolean', 'null'], 'description' => 'Whether there is one' }
          elsif association.macro == :has_many && association.active_record.column_names.include?((association.counter_cache_column || "#{association.plural_name}_count").to_s)
            # activerecord-filter tests a has_many with its counter cache
            { 'type' => 'boolean', 'description' => 'Whether there are any' }
          end

          filter = if association.polymorphic?
            {
              'type' => 'object',
              'properties' => {
                'as' => { 'type' => 'string', 'description' => 'The model to filter on' }
              },
              'required' => ['as'],
              'description' => 'Filtered by the wheres of the model named by `as`'
            }
          else
            json_schema_ref(defs, json_schema_name(association.klass, 'Where'), 'where', model: association.klass)
          end

          json.set! key, exists ? { 'anyOf' => [exists, filter] } : filter

          if association.collection?
            ids_key = "#{key.singularize}_ids"
            ids_permit = json_schema_wheres(association.klass)['id']
            ids_column = association.klass.columns_hash['id']
            if ids_key.sub(/_ids\z/, 's') == key && ids_permit && ids_column
              json.set! ids_key, json_schema_column_where(association.klass, ids_column, ids_permit)
            end
          end
        else
          json.set! key, {}
        end
      end
    end
    json.set! 'patternProperties', pattern_properties if pattern_properties.any?
    json.set! 'additionalProperties', false
  end

  json.child! do
    json.merge!({
      'type' => 'array',
      'items' => { 'anyOf' => [{ 'enum' => ['AND', 'OR'] }, { '$ref' => "#/$defs/#{json_schema_name(model, 'Where')}" }] }
    })
  end
end
