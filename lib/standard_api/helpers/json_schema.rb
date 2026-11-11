module StandardAPI
  module Helpers
    # The helpers the schema/read, schema/write and schema/query views
    # (application/read_schema, write_schema and query_schema, and the
    # application/json_schema partials) are built with, included in
    # StandardAPI::Helpers.
    #
    # The views lay out each JSON Schema: its objects, properties, required and
    # the records and associations they recurse into. These describe the values
    # in it, ie. an attribute from its definition in schemas_for(model), and
    # read the controller's ACL for the views, so each schema only describes
    # what the ACL permits.
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

      # The JSON Schema for a Helpers#schemas_for `type`, or an empty schema
      # for a type it doesn't know
      def json_schema_for_type(type)
        case type
        when 'string', 'text', 'citext', 'inet', 'cidr', 'macaddr', 'ltree'
          {type: 'string'}
        when 'uuid'
          {type: 'string', format: 'uuid'}
        when 'integer'
          {type: 'integer'}
        when 'float'
          {type: 'number'}
        when 'decimal', 'money'
          # A BigDecimal renders as a String in JSON, and either is accepted
          {type: ['number', 'string']}
        when 'boolean'
          {type: 'boolean'}
        when 'date'
          {type: 'string', format: 'date'}
        when 'datetime', 'timestamp', 'timestamptz', 'time'
          # A time column renders as a full timestamp, not "HH:MM:SS"
          {type: 'string', format: 'date-time'}
        when 'interval'
          {type: 'string', format: 'duration'}
        when 'json', 'jsonb', 'hstore'
          {type: 'object'}
        when 'binary'
          {type: 'string', contentMediaType: 'application/octet-stream'}
        else
          {}
        end
      end

      # The ACL, read from the controller. These are private there.

      # The ACL's wheres for +model+, as name => operators
      def json_schema_wheres(model)
        model ? controller.send(:normalize_where_permit, controller.send(:wheres_for, model)) : {}
      end

      def json_schema_orders(model)
        model ? Array(controller.send(:orders_for, model)).flatten : []
      end

      def json_schema_required_orders
        controller.send(:required_orders)
      end

      # The ACL's includes for +model+, normalized
      def json_schema_includes(model)
        controller.send(:normalize_includes, controller.send(:includes_for, model))
      end

      # The attributes the ACL's +attributes+ permit for +model+: names, and
      # Hashes of a name to its permitted Array ([]) or Hash
      def json_schema_attributes(model)
        Array(controller.model_attributes(model)).flatten
      end

      # The associations the ACL's +nested+ permits for +model+, as
      # AccessControlList#filter_model_params reads them
      def json_schema_nested(model)
        method = "nested_#{json_schema_param_key(model)}_attributes"
        return [] if !controller.respond_to?(method, true)

        controller.send(method).filter_map { |relation| model.reflect_on_association(relation) }
      end

      # Whether the ACL's +filter+ filters the params of +model+, so they
      # aren't described
      def json_schema_filtered?(model)
        controller.respond_to?("filter_#{json_schema_param_key(model)}_params", true)
      end

      # The key #create and #update read +model+'s params from
      def json_schema_param_key(model)
        controller.send(:model_name, model)
      end

      # Models

      def json_schema_description(model)
        model.connection.table_comment(model.table_name)
      end

      # schemas_for(model), as name => definition
      def json_schema_definitions(model)
        @json_schema_definitions ||= {}
        @json_schema_definitions[model] ||= schemas_for(model).index_by { |definition| definition[:name].to_s }
      end

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
          json_schema_value(model, definition)
        end

        schema = { 'type' => 'array', 'items' => schema } if definition[:array]
        # Only a NOT NULL column can't be null
        schema = json_schema_nullable(schema) if definition[:null] != false
        schema['description'] = definition[:comment] if definition[:comment]
        schema
      end

      # The JSON Schema of the attribute +name+ from its definition, with its
      # validations, or {} if the Schema doesn't declare it. It's readOnly
      # when the definition is read only: an attr_readonly attribute, which
      # can be set on create but not changed, or one the Schema says is.
      def json_schema_attribute_write(model, name)
        definition = json_schema_definitions(model)[name.to_s]
        return {} if !definition

        schema = json_schema_value(model, definition, validations: true)
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
        definition ? json_schema_value(association.klass, definition) : {}
      end

      # +operators+ are canonical names, as normalize_where_permit gives them,
      # or :all
      def json_schema_column_where(model, column, operators)
        definition = json_schema_definitions(model)[column.name]
        operators = json_schema_operators(column, definition) if operators == :all
        operators = operators.map(&:to_s)
        value = definition ? json_schema_value(model, definition) : {}
        value = { 'type' => 'array', 'items' => value } if column.array

        any_of = []
        any_of << value << { 'type' => ['boolean', 'null'] } if operators.include?('eq')
        any_of << { 'type' => 'array', 'items' => value } if operators.include?('in') && !column.array
        any_of << {
          'type' => 'object',
          'properties' => operators.index_with { |operator| json_schema_operator_value(operator, value) },
          'additionalProperties' => false,
          'minProperties' => 1
        }

        { 'anyOf' => any_of }
      end

      # The JSON Schema of a where on +association+: the wheres of its model,
      # or whether it has any records where activerecord-filter can test that
      def json_schema_association_where(defs, association)
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
          json_schema_where_ref(defs, association.klass)
        end

        exists ? { 'anyOf' => [exists, filter] } : filter
      end

      # Mirrors StandardAPI::Orders#sanitize_orders: a name +permit+ lists, an
      # object of them, or an Array of either. The object is rendered into
      # $defs as +name+ followed by "Object", by
      # application/json_schema/_order_object. +model+ is nil under a Hash in
      # +permit+. An empty +permit+ accepts nothing.
      def json_schema_order(defs, permit, model, name)
        permit = Array(permit).flatten
        return { 'not' => {} } if permit.empty?

        names = { 'type' => 'string', 'enum' => json_schema_order_names(model, permit) }
        object = json_schema_ref(defs, "#{name}Object", 'order_object', permit: permit, model: model, name: name)

        { 'anyOf' => [names, object, { 'type' => 'array', 'items' => { 'anyOf' => [names, object] } }] }
      end

      # The names +permit+ lets +model+ be ordered by, an association's as
      # "association.column". +model+ is nil under a Hash in +permit+.
      def json_schema_order_names(model, permit)
        permit.flat_map do |entry|
          if entry.is_a?(Hash)
            entry.flat_map { |name, subpermit| Array(subpermit).flatten.map { |column| "#{name}.#{column}" } }
          elsif (association = model&.reflect_on_association(entry.to_s)) && !association.polymorphic?
            json_schema_orders(association.klass).reject { |x| x.is_a?(Hash) }.map { |column| "#{entry}.#{column}" }
          else
            [entry.to_s]
          end
        end
      end

      # Mirrors StandardAPI::Includes#sanitize_includes: an object of the
      # associations +permit+ lists, a name, or an Array of either. +model+ is
      # nil under a polymorphic association, where a +where+ can't be checked.
      #
      # The object is rendered into $defs as +name+, by
      # application/json_schema/_include_object, and the includes under it are
      # named after +prefix+. The include of an association has the +options+
      # (+where+, +order+, +limit+, +distinct+, +distinct_on+, +when+) that
      # apply to included records; the top level has none.
      def json_schema_include(defs, permit, model, name:, prefix: name, options: true)
        names = { 'type' => 'string', 'enum' => permit.keys.map(&:to_s) - StandardAPI::Controller::RESERVED_INCLUDE_KEYS }
        object = json_schema_ref(defs, name, 'include_object', permit: permit, model: model, prefix: prefix, options: options)

        { 'anyOf' => [object, names, { 'type' => 'array', 'items' => { 'anyOf' => [names, object] } }] }
      end

      # What the association +name+ of +model+, permitted +subpermit+, can be
      # included as: true, or its own include. That is named after +prefix+,
      # unless it's the include of the association's model.
      def json_schema_association_include(defs, model, name, subpermit, prefix)
        association = model&.reflect_on_association(name)
        sub_name = "#{prefix.to_s.delete_suffix('Include')}#{name.to_s.camelize}Include"

        sub = if association && !association.polymorphic?
          if subpermit.empty?
            klass = association.klass
            json_schema_include(defs, json_schema_includes(klass), klass, name: json_schema_name(klass, 'Include'))
          else
            json_schema_include(defs, subpermit, association.klass, name: sub_name)
          end
        elsif subpermit.present?
          json_schema_include(defs, subpermit, nil, name: sub_name)
        end

        # The +when+ of an include is checked against the model it's on, and
        # the include's schema is shared by every model including it
        if sub && model
          sub = { 'allOf' => [sub, { 'properties' => { 'when' => json_schema_when_ref(defs, model) } }] }
        end

        included = { 'enum' => [true, 'true'] }
        sub ? { 'anyOf' => [included, sub] } : included
      end

      # Mirrors StandardAPI::Includes#check_include_when: the attributes of
      # +model+ its ACL wheres permit an +eq+ on, each compared with its value
      # as application/_record renders it
      def json_schema_when(model)
        definitions = json_schema_definitions(model)
        properties = {}
        json_schema_wheres(model).each do |key, operators|
          next if !model.attribute_names.include?(key)
          next if operators != :all && !operators.include?('eq')

          properties[key] = definitions[key] ? json_schema_attribute_read(model, definitions[key]) : {}
        end

        { 'type' => 'object', 'properties' => properties, 'additionalProperties' => false }
      end

      # The options of an include of +model+, which is nil under a polymorphic
      # association
      def json_schema_include_options(defs, model)
        options = {}
        options['where'] = json_schema_where_ref(defs, model) if model && json_schema_wheres(model).any?
        options['order'] = json_schema_order_ref(defs, model) if model && json_schema_orders(model).any?
        options['limit'] = { 'type' => 'integer', 'minimum' => 0 }
        options['distinct'] = { 'type' => 'boolean' }

        # Passed through by #sanitize_includes, but not checked by the ACL
        options['distinct_on'] = json_schema_unchecked(json_schema_columns, 'Columns to select distinct included records on, passed to `distinct_on`.')
        options['when'] = {
          'type' => 'object',
          'description' => 'Only include for the including records whose rendered value of each attribute equals the given value. #index only.'
        }
        options
      end

      # The params of #index and #calculate that are the same whatever the ACL
      # permits
      def json_schema_query_options(model)
        column_name = { 'type' => 'string', 'enum' => model.column_names }

        {
          'limit' => {
            'type' => 'integer',
            'minimum' => 0,
            'maximum' => resource_limit,
            'default' => default_limit
          }.compact,
          'offset' => { 'type' => 'integer', 'minimum' => 0 },
          'distinct' => { 'type' => 'boolean' },
          # Mirrors Controller#group_by, which only accepts the model's columns
          'group_by' => {
            'anyOf' => [column_name, { 'type' => 'array', 'items' => column_name }],
            'description' => 'Columns of the model to group by. #calculate returns an object keyed by group.'
          },
          # Used by #resources and #calculate_selects, but not checked by the ACL
          'distinct_on' => json_schema_unchecked(json_schema_columns, 'Columns to select distinct rows on, passed to `distinct_on`. Takes precedence over `distinct`.'),
          'join' => json_schema_unchecked(
            { 'type' => 'string', 'enum' => model.reflect_on_all_associations.map { |a| a.name.to_s } },
            'An association to inner join, passed to `joins`.'
          ),
          'select' => json_schema_unchecked(json_schema_select, 'The calculations #calculate returns.')
        }
      end

      # $defs

      # The name in $defs of the +kind+ ("Where", "Order", "When" or
      # "Include") of +model+. The top level's order object and include are
      # "OrderObject" and "Include".
      def json_schema_name(model, kind)
        "#{model.name.gsub('::', '')}#{kind}"
      end

      # A $ref to +name+ in $defs, rendered there by the
      # application/json_schema +partial+ with +locals+ the first time.
      # query_schema renders $defs after everything that refers into it.
      def json_schema_ref(defs, name, partial, **locals)
        defs[name] ||= { partial: "application/json_schema/#{partial}", locals: locals }
        { '$ref' => "#/$defs/#{name}" }
      end

      def json_schema_where_ref(defs, model)
        json_schema_ref(defs, json_schema_name(model, 'Where'), 'where', model: model)
      end

      # A $ref to +name+ in $defs, where it is the schema the block gives the
      # first time
      def json_schema_def(defs, name)
        defs[name] ||= { schema: yield }
        { '$ref' => "#/$defs/#{name}" }
      end

      def json_schema_order_ref(defs, model)
        name = json_schema_name(model, 'Order')
        json_schema_def(defs, name) { json_schema_order(defs, json_schema_orders(model), model, name) }
      end

      def json_schema_when_ref(defs, model)
        json_schema_def(defs, json_schema_name(model, 'When')) { json_schema_when(model) }
      end

      # Fixed schemas

      def json_schema_direction
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

      # +schema+, described as a param the ACL doesn't check
      def json_schema_unchecked(schema, description)
        schema.merge('description' => "#{description} Not checked by the ACL.")
      end

      # A String or an Array of them, ie. columns as a name or "table.column"
      def json_schema_columns
        { 'anyOf' => [{ 'type' => 'string' }, { 'type' => 'array', 'items' => { 'type' => 'string' } }] }
      end

      # Mirrors Controller#calculate_selects
      def json_schema_select
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

      private

      # +schema+ allowing null
      def json_schema_nullable(schema)
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

      # The JSON Schema of a value of the attribute a definition describes, from
      # its +type+ (json_schema_for_type) and +enum+, and with +validations+ its
      # validations. Not nullable: the caller decides.
      def json_schema_value(model, definition, validations: false)
        schema = json_schema_for_type(definition[:type]).deep_stringify_keys
        json_schema_validations(schema, model, definition) if validations
        # Rails enums are described by their names
        schema['enum'] = definition[:enum] if definition[:enum]
        schema
      end

      # The validations of a definition, as JSON Schema. A presence validation
      # is in the definition's +required+.
      def json_schema_validations(schema, model, definition)
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

      def json_schema_operators(column, definition)
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

      def json_schema_operator_value(operator, value)
        case operator
        when 'eq', 'neq' then { 'anyOf' => [value, { 'type' => 'null' }] }
        when 'gt', 'gte', 'lt', 'lte' then value
        when 'in', 'not_in' then { 'type' => 'array', 'items' => value }
        when 'like', 'ilike', 'has_key' then { 'type' => 'string' }
        when 'has_keys', 'has_any_key', 'ts_match' then json_schema_columns
        when 'contains', 'contained_by', 'excludes', 'overlaps', 'not_overlaps'
          value['type'] == 'array' ? value : {}
        else
          {}
        end
      end

    end
  end
end
