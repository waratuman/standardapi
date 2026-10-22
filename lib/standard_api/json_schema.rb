module StandardAPI
  # Included in StandardAPI::Controller. Builds the JSON Schemas served by the
  # write_schema, read_schema and query_schema actions from the ACL, so each
  # only describes what the ACL permits. Params the ACL doesn't check yet are
  # described as they're used, and say so. Attributes are described from
  # their definitions in schemas_for(model), after the ACL's +schemas+.
  module JSONSchema

    DIALECT = 'https://json-schema.org/draft/2020-12/schema'.freeze

    # The operators presented for a column permitted with any operator, by
    # its schemas_for type. activerecord-filter accepts every operator on every
    # column and leaves it to the database to reject one that doesn't apply, so
    # this narrows the list to the ones that do. A type not listed, and an
    # enum, gets EQUALITY_OPERATORS. Operators an ACL lists for a column are
    # presented as listed.
    COMPARISON_OPERATORS = %i(eq neq in not_in gt gte lt lte).freeze
    EQUALITY_OPERATORS = %i(eq neq in not_in).freeze
    TYPE_OPERATORS = {
      string:    COMPARISON_OPERATORS + %i(like ilike),
      text:      COMPARISON_OPERATORS + %i(like ilike),
      citext:    COMPARISON_OPERATORS + %i(like ilike),
      integer:   COMPARISON_OPERATORS,
      float:     COMPARISON_OPERATORS,
      decimal:   COMPARISON_OPERATORS,
      date:      COMPARISON_OPERATORS,
      datetime:  COMPARISON_OPERATORS,
      time:      COMPARISON_OPERATORS,
      boolean:   EQUALITY_OPERATORS,
      uuid:      EQUALITY_OPERATORS,
      binary:    EQUALITY_OPERATORS,
      inet:      EQUALITY_OPERATORS,
      ltree:     COMPARISON_OPERATORS,
      json:      %i(eq neq contains contained_by has_key has_keys has_any_key),
      jsonb:     %i(eq neq contains contained_by has_key has_keys has_any_key),
      hstore:    %i(eq neq contains contained_by has_key has_keys has_any_key),
      geometry:  %i(eq contains intersects overlaps within),
      geography: %i(eq contains intersects overlaps within),
      tsvector:  %i(ts_match)
    }.freeze
    ARRAY_OPERATORS = %i(eq neq contains contained_by excludes overlaps not_overlaps).freeze
    RANGE_OPERATORS = %i(eq neq contains contained_by overlaps not_overlaps ends_before ends_by starts_after starts_by adjacent_to).freeze

    private

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

    # The shape #show renders for +model+ with +includes+, ie. each record
    # #index renders.
    def read_schema_for(model, includes)
      {
        '$schema' => DIALECT,
        'title' => model.model_name.human
      }.merge(record_read_schema(model, includes))
    end

    # The shape of the params #index and #calculate accept for +model+: the
    # +where+, +order+ and +include+ the ACL permits, +limit+, +offset+ and
    # +distinct+, and the unchecked +distinct_on+, +join+, +group_by+ and
    # +select+.
    def query_schema_for(model)
      defs = {}
      properties = {}

      properties['where'] = where_ref(model, defs) if normalize_where_permit(wheres_for(model)).any?

      order = order_schema(orders_for(model) | required_orders, model, defs)
      properties['order'] = order if order

      include_permit = normalize_includes(includes_for(model))
      properties['include'] = include_schema(include_permit, model, defs) if include_permit.any?

      properties['limit'] = {
        'type' => 'integer',
        'minimum' => 0,
        'maximum' => resource_limit,
        'default' => default_limit
      }.compact
      properties['offset'] = { 'type' => 'integer', 'minimum' => 0 }
      properties['distinct'] = { 'type' => 'boolean' }

      # Used by #resources and #calculate_selects, but not checked by the ACL
      properties['distinct_on'] = unchecked(columns_schema, 'Columns to select distinct rows on, passed to `distinct_on`. Takes precedence over `distinct`.')
      properties['join'] = unchecked(
        { 'type' => 'string', 'enum' => model.reflect_on_all_associations.map { |a| a.name.to_s } },
        'An association to inner join, passed to `joins`.'
      )
      properties['group_by'] = unchecked(columns_schema, 'Columns to group by, passed to `group`. #calculate returns an object keyed by group.')
      properties['select'] = unchecked(select_schema, 'The calculations #calculate returns.')

      {
        '$schema' => DIALECT,
        'title' => model.model_name.human.pluralize,
        'type' => 'object',
        'properties' => properties,
        # #index needs a limit when there is no default; #calculate, which
        # takes a select, doesn't
        'anyOf' => ([{ 'required' => ['limit'] }, { 'required' => ['select'] }] if resource_limit && !default_limit),
        '$defs' => (defs if defs.any?)
      }.compact
    end

    def model_description(model)
      model.connection.table_comment(model.table_name)
    end

    # schemas_for(model), as name => definition
    def definitions_for(model)
      @definitions_for ||= {}
      @definitions_for[model] ||= schemas_for(model).index_by { |definition| definition.fetch(:name).to_s }
    end

    # == Write

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
            properties[name.to_s] = if permit == []
              { 'type' => 'array' }
            else
              { 'type' => 'object' }
            end
          end
        else
          name = entry.to_s
          properties[name] = attribute_write_schema(model, name)
          required << name if !nested && definitions[name]&.[](:required)
        end
      end

      nested_write_schemas(model, path + [model]).each do |name, schema|
        properties[name] = schema
      end

      {
        'type' => 'object',
        'properties' => properties,
        'additionalProperties' => false,
        'required' => (required if required.any?)
      }.compact
    end

    # The JSON Schema of the attribute +name+ from its definition, with its
    # validations, or {} if the definitions leave it out. An attr_readonly
    # attribute is readOnly: it can be set on create, but not changed.
    def attribute_write_schema(model, name)
      definition = definitions_for(model)[name.to_s]
      return {} if !definition

      schema = definition_value_schema(model, definition, validations: true)
      schema = { 'type' => 'array', 'items' => schema } if definition[:array]
      # Only a NOT NULL column can't be null; one without a column, or a
      # definition that doesn't say, has a nil +null+
      schema = nullable(schema) if definition[:null] != false

      # For an array these describe the array, not its items
      schema['readOnly'] = true if model.readonly_attribute?(name.to_s)
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

    def id_schema(association)
      return {} if association.polymorphic?

      definition = definitions_for(association.klass)[association.klass.primary_key]
      definition ? definition_value_schema(association.klass, definition) : {}
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
        end
      end
    end

    # == Read

    def record_read_schema(model, includes)
      if model_partial(model) != 'application/record'
        return {
          'type' => 'object',
          'description' => "Rendered by #{model_partial(model)}"
        }
      end

      properties = {}
      definitions_for(model).each do |name, definition|
        properties[name] = attribute_read_schema(model, definition)
      end
      # Columns are always rendered. Other attributes may not be loaded, ie.
      # under a partial select, or may be ones the ACL's schemas adds.
      required = properties.keys & model.column_names

      includes.each do |name, subincludes|
        next if StandardAPI::Controller::RESERVED_INCLUDE_KEYS.include?(name.to_s)

        association = model.reflect_on_association(name)
        required << name.to_s
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

      # An ACL exclude can leave out any of them
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
        'required' => required
      }.compact
    end

    # The JSON Schema of the attribute a definition describes, as
    # application/_record serializes it. Validations aren't applied: a record
    # saved before one was added may not pass it.
    def attribute_read_schema(model, definition)
      schema = case definition.fetch(:type)
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

    # == Query

    def schema_name(model, kind)
      "#{model.name.gsub('::', '')}#{kind}"
    end

    # A $ref to the where schema of +model+, built into +defs+ the first time
    def where_ref(model, defs)
      name = schema_name(model, 'Where')
      if !defs.key?(name)
        defs[name] = nil
        defs[name] = where_schema(model, defs)
      end
      { '$ref' => "#/$defs/#{name}" }
    end

    # Mirrors StandardAPI::Wheres#check_wheres: a Hash of permitted keys, or
    # an Array of them joined by "AND" and "OR".
    def where_schema(model, defs)
      permit = normalize_where_permit(wheres_for(model))
      properties = {}
      pattern_properties = {}

      permit.each do |key, operators|
        if model.filters.has_key?(key)
          properties[key] = { 'description' => "The #{key} filter" }
        elsif column = model.columns_hash[key]
          properties[key] = column_where_schema(model, column, operators)
          if [:json, :jsonb].include?(column.type)
            pattern_properties["^#{Regexp.escape(key)}\\..+$"] = properties[key]
          end
        elsif association = model.reflect_on_association(key)
          properties[key] = association_where_schema(association, defs)

          if association.collection?
            ids_key = "#{key.singularize}_ids"
            ids_permit = normalize_where_permit(wheres_for(association.klass))['id']
            ids_column = association.klass.columns_hash['id']
            if ids_key.sub(/_ids\z/, 's') == key && ids_permit && ids_column
              properties[ids_key] = column_where_schema(association.klass, ids_column, ids_permit)
            end
          end
        else
          properties[key] = {}
        end
      end

      object = {
        'type' => 'object',
        'properties' => properties,
        'patternProperties' => (pattern_properties if pattern_properties.any?),
        'additionalProperties' => false
      }.compact

      self_ref = { '$ref' => "#/$defs/#{schema_name(model, 'Where')}" }
      # A bare value is checked as an `eq` on id, but isn't presented:
      # activerecord-filter can't filter on one from a query string.
      {
        'anyOf' => [
          object,
          { 'type' => 'array', 'items' => { 'anyOf' => [{ 'enum' => ['AND', 'OR'] }, self_ref] } }
        ]
      }
    end

    def association_where_schema(association, defs)
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
          'description' => "Filtered by the wheres of the model named by `as`"
        }
      else
        where_ref(association.klass, defs)
      end

      exists ? { 'anyOf' => [exists, filter] } : filter
    end

    # +operators+ are canonical names, as normalize_where_permit gives them,
    # or :all
    def column_where_schema(model, column, operators)
      definition = definitions_for(model)[column.name]
      operators = column_operators(column, definition) if operators == :all
      operators = operators.map(&:to_s)
      value = definition ? definition_value_schema(model, definition) : {}
      value = { 'type' => 'array', 'items' => value } if column.array

      any_of = []
      any_of << value << { 'type' => ['boolean', 'null'] } if operators.include?('eq')
      any_of << { 'type' => 'array', 'items' => value } if operators.include?('in') && !column.array
      any_of << {
        'type' => 'object',
        'properties' => operators.index_with { |operator| operator_value_schema(operator, value) },
        'additionalProperties' => false,
        'minProperties' => 1
      }

      { 'anyOf' => any_of }
    end

    def column_operators(column, definition)
      if column.array
        ARRAY_OPERATORS
      elsif column.type.to_s.end_with?('range')
        RANGE_OPERATORS
      elsif !definition || definition[:enum]
        EQUALITY_OPERATORS
      else
        TYPE_OPERATORS.fetch(definition[:type]&.to_sym, EQUALITY_OPERATORS)
      end
    end

    def operator_value_schema(operator, value)
      strings = { 'anyOf' => [{ 'type' => 'string' }, { 'type' => 'array', 'items' => { 'type' => 'string' } }] }

      case operator
      when 'eq', 'neq' then { 'anyOf' => [value, { 'type' => 'null' }] }
      when 'gt', 'gte', 'lt', 'lte' then value
      when 'in', 'not_in' then { 'type' => 'array', 'items' => value }
      when 'like', 'ilike', 'has_key' then { 'type' => 'string' }
      when 'has_keys', 'has_any_key', 'ts_match' then strings
      when 'contains', 'contained_by', 'excludes', 'overlaps', 'not_overlaps'
        value['type'] == 'array' ? value : {}
      else
        {}
      end
    end

    # Mirrors StandardAPI::Orders#sanitize_orders
    def order_schema(permit, model, defs)
      permit = Array(permit).flatten
      return nil if permit.empty?

      names = []
      properties = {}

      permit.each do |entry|
        if entry.is_a?(Hash)
          entry.each do |name, subpermit|
            name = name.to_s
            names.concat(Array(subpermit).flatten.map { |column| "#{name}.#{column}" })
            properties[name] = order_schema(subpermit, nil, defs)
          end
          next
        end

        name = entry.to_s
        association = model&.reflect_on_association(name)
        if association && !association.polymorphic?
          columns = Array(orders_for(association.klass)).flatten.reject { |x| x.is_a?(Hash) }
          names.concat(columns.map { |column| "#{name}.#{column}" })
          properties[name] = order_ref(association.klass, defs)
        else
          names << name
          properties[name] = direction_schema
        end
      end

      object = {
        'type' => 'object',
        'properties' => properties,
        'additionalProperties' => false,
        'minProperties' => 1
      }
      name_schema = { 'type' => 'string', 'enum' => names }

      {
        'anyOf' => [
          name_schema,
          object,
          { 'type' => 'array', 'items' => { 'anyOf' => [name_schema, object] } }
        ]
      }
    end

    def order_ref(model, defs)
      name = schema_name(model, 'Order')
      if !defs.key?(name)
        defs[name] = nil
        defs[name] = order_schema(orders_for(model), model, defs) || { 'not' => {} }
      end
      { '$ref' => "#/$defs/#{name}" }
    end

    def direction_schema
      nulls = { 'enum' => ['nulls_first', 'nulls_last'] }
      {
        'anyOf' => [
          { 'enum' => ['asc', 'desc'] },
          {
            'type' => 'object',
            'properties' => { 'asc' => nulls, 'desc' => nulls },
            'additionalProperties' => false,
            'minProperties' => 1,
            'maxProperties' => 1
          }
        ]
      }
    end

    # Mirrors StandardAPI::Includes#sanitize_includes. +model+ is nil under a
    # polymorphic association, where a +where+ can't be checked.
    #
    # The include of an association is an object built into +defs+ as +name+,
    # with the options (+where+, +limit+, +distinct+, +order+, +distinct_on+,
    # +when+) that apply to included records. The top level, without a
    # +name+, has no options and is inline.
    def include_schema(permit, model, defs, name: nil)
      names = permit.keys.map(&:to_s) - StandardAPI::Controller::RESERVED_INCLUDE_KEYS
      object = if name
        if !defs.key?(name)
          defs[name] = nil
          defs[name] = include_object_schema(permit, model, defs, name, options: true)
        end
        { '$ref' => "#/$defs/#{name}" }
      else
        include_object_schema(permit, model, defs, model && schema_name(model, ''), options: false)
      end
      name_schema = { 'type' => 'string', 'enum' => names }

      {
        'anyOf' => [
          object,
          name_schema,
          { 'type' => 'array', 'items' => { 'anyOf' => [name_schema, object] } }
        ]
      }
    end

    def include_object_schema(permit, model, defs, prefix, options:)
      properties = {}

      permit.each do |name, subpermit|
        next if StandardAPI::Controller::RESERVED_INCLUDE_KEYS.include?(name.to_s)

        association = model&.reflect_on_association(name)
        sub_name = "#{prefix.to_s.delete_suffix('Include')}#{name.to_s.camelize}Include"
        sub = if association && !association.polymorphic?
          if subpermit.empty?
            include_ref(association.klass, defs)
          else
            include_schema(subpermit, association.klass, defs, name: sub_name)
          end
        elsif subpermit.present?
          include_schema(subpermit, nil, defs, name: sub_name)
        end

        # The +when+ of an include is checked against the model it's on, and
        # the include's schema is shared by every model including it
        if sub && model
          sub = { 'allOf' => [sub, { 'properties' => { 'when' => when_ref(model, defs) } }] }
        end

        included = { 'enum' => [true, 'true'] }
        properties[name.to_s] = sub ? { 'anyOf' => [included, sub] } : included
      end

      if options
        properties['where'] = where_ref(model, defs) if model && normalize_where_permit(wheres_for(model)).any?
        properties['limit'] = { 'type' => 'integer', 'minimum' => 0 }
        properties['distinct'] = { 'type' => 'boolean' }

        # Passed through by #sanitize_includes, but not checked by the ACL
        properties['order'] = unchecked(
          { 'anyOf' => [{ 'type' => 'object' }, { 'type' => 'array' }] },
          'The order of the included records, passed to `reorder`.'
        )
        properties['distinct_on'] = unchecked(columns_schema, 'Columns to select distinct included records on, passed to `distinct_on`.')
        properties['when'] = {
          'type' => 'object',
          'description' => 'Only include for the including records whose rendered value of each attribute equals the given value. #index only.'
        }
      end

      { 'type' => 'object', 'properties' => properties, 'additionalProperties' => false }
    end

    # A $ref to the +when+ of an include on +model+, built into +defs+ the
    # first time
    def when_ref(model, defs)
      name = schema_name(model, 'When')
      defs[name] ||= when_schema(model)
      { '$ref' => "#/$defs/#{name}" }
    end

    # Mirrors StandardAPI::Includes#check_include_when: the attributes of
    # +model+ its ACL wheres permit an +eq+ on, each compared with its value
    # as application/_record renders it
    def when_schema(model)
      properties = {}
      normalize_where_permit(wheres_for(model)).each do |key, operators|
        next if !model.attribute_names.include?(key)
        next if operators != :all && !operators.include?('eq')

        definition = definitions_for(model)[key]
        properties[key] = definition ? attribute_read_schema(model, definition) : {}
      end

      { 'type' => 'object', 'properties' => properties, 'additionalProperties' => false }
    end

    def include_ref(model, defs)
      include_schema(normalize_includes(includes_for(model)), model, defs, name: schema_name(model, 'Include'))
    end

    # +schema+, described as a param the ACL doesn't check
    def unchecked(schema, description)
      schema.merge('description' => "#{description} Not checked by the ACL.")
    end

    # A column, or columns, as a name or "table.column"
    def columns_schema
      { 'anyOf' => [{ 'type' => 'string' }, { 'type' => 'array', 'items' => { 'type' => 'string' } }] }
    end

    # Mirrors Controller#calculate_selects
    def select_schema
      column = {
        'anyOf' => [
          { 'type' => 'string', 'description' => 'A column, "table.column", or "*"' },
          {
            'type' => 'object',
            'properties' => { 'distinct' => { 'type' => 'string' } },
            'required' => ['distinct'],
            'additionalProperties' => false
          }
        ]
      }
      calculation = {
        'type' => 'object',
        'properties' => %w(minimum maximum average sum count).index_with { column },
        'additionalProperties' => false,
        'minProperties' => 1
      }

      { 'anyOf' => [calculation, { 'type' => 'array', 'items' => calculation }] }
    end

    # == Values

    # The JSON Schema of a value of the attribute a definition describes, from
    # its +type+ (Helpers#json_schema_for_type) and +enum+, and with
    # +validations+ its validations. Not nullable: the caller decides.
    def definition_value_schema(model, definition, validations: false)
      schema = helpers.json_schema_for_type(definition.fetch(:type)).deep_stringify_keys
      apply_validations(schema, model, definition) if validations
      # Rails enums are described by their names
      schema['enum'] = definition[:enum] if definition[:enum]
      schema
    end

    def nullable(schema)
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
