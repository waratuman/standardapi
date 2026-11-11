module StandardAPI
  module Helpers
    # Builds the JSON Schemas served at schema/read, schema/write and
    # schema/query, included in StandardAPI::Helpers. Each is built from the
    # ACL, read from the controller, so it only describes what the ACL
    # permits. Attributes are described from their definitions in
    # schemas_for(model), so only what the model's Schema declares. Params the
    # ACL doesn't check yet are described as they're used, and say so.
    #
    # read_schema_for, write_schema_for and query_schema_for are delegated to
    # from the controller, like schemas_for, so a caller can build a schema on
    # a controller bound to a request and validate in-process, without
    # dispatching the action.
    #
    # The private helpers are prefixed json_schema_, as they're in every view.
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
        when 'json', 'jsonb'
          # Holds any JSON value: an object, an array or a scalar
          {}
        when 'hstore'
          {type: 'object'}
        when 'binary'
          {type: 'string', contentMediaType: 'application/octet-stream'}
        else
          {}
        end
      end

      # The shape #show renders for +model+ with +includes+, ie. each record
      # #index renders. +includes+ are normalized and checked against the ACL,
      # as Controller#includes gives them.
      def read_schema_for(model, includes)
        {
          '$schema' => DIALECT,
          'title' => model.model_name.human
        }.merge(json_schema_record_read(model, includes))
      end

      # The shape of the params #create and #update accept for +model+: the
      # attributes the ACL's +attributes+ permit, and the associations its
      # +nested+ permits. +required+ lists what a create needs; an update needs
      # none of it.
      def write_schema_for(model)
        schema = json_schema_record_write(model, [])
        if schema['required']
          schema['$comment'] = 'required applies to a create. An update may send any of the properties.'
        end

        {
          '$schema' => DIALECT,
          'title' => model.model_name.human,
          'description' => json_schema_description(model),
          'type' => 'object',
          'properties' => { json_schema_param_key(model) => schema }
        }.compact
      end

      # The shape of the params #index and #calculate accept for +model+: the
      # +where+, +order+ and +include+ the ACL permits, +limit+, +offset+,
      # +distinct+, +group_by+, and the unchecked
      # +distinct_on+, +join+ and +select+.
      #
      # The where, order and include of each other model reachable through a
      # permitted association are built into $defs. With +ref+, they are left to
      # the caller instead: it is called as `ref.(model, kind)`, +kind+ being
      # "Where", "Order" or "Include", and what it returns is used in place of
      # that model's schema, ie. a $ref to the caller's own URI. Returning nil
      # builds it into $defs as without +ref+.
      #
      # With +ref+ the schema is one of a set that refer into each other, so
      # the where, order and include of +model+ itself are in its $defs too,
      # as its name without "::" followed by the kind, for the others to
      # refer to:
      #
      #   query_schema_for(Property, ref: ->(model, kind) {
      #     { '$ref' => "standardmcp://schema/#{model.model_name.plural}#/$defs/#{model.name.gsub('::', '')}#{kind}" }
      #   })
      def query_schema_for(model, ref: nil)
        defs = Defs.new(model, ref)
        properties = {}

        properties['where'] = json_schema_where_ref(model, defs) if json_schema_wheres(model).any?

        order = json_schema_order(json_schema_orders(model) | json_schema_required_orders, model, defs, 'Order')
        properties['order'] = order if order

        include_permit = json_schema_includes(model)
        if include_permit.any?
          properties['include'] = json_schema_include(include_permit, model, defs,
            name: 'Include', prefix: json_schema_name(model, ''), options: false)
        end

        # What the other schemas of a set refer to
        if ref
          json_schema_where_ref(model, defs)
          json_schema_order_ref(model, defs)
          json_schema_include_ref(model, defs)
        end

        properties['limit'] = {
          'type' => 'integer',
          'minimum' => 0,
          'maximum' => resource_limit,
          'default' => default_limit
        }.compact
        properties['offset'] = { 'type' => 'integer', 'minimum' => 0 }
        properties['distinct'] = { 'type' => 'boolean' }

        # Controller#group_by only accepts the model's columns, and #joins its
        # associations. Neither is listed: a Schema needn't declare a column,
        # nor an ACL permit an association, and their names would be shown.
        column_name = { 'type' => 'string' }
        properties['group_by'] = {
          'anyOf' => [column_name, { 'type' => 'array', 'items' => column_name }],
          'description' => 'Columns of the model to group by, each by its name alone. #calculate returns an object keyed by group.'
        }

        # Used by #resources and #calculate_selects, but not checked by the ACL
        properties['distinct_on'] = json_schema_unchecked(json_schema_columns, 'Columns to select distinct rows on, passed to `distinct_on`. Takes precedence over `distinct`.')
        properties['join'] = json_schema_unchecked({ 'type' => 'string' }, 'An association of the model to inner join, passed to `joins`.')
        properties['select'] = json_schema_unchecked(json_schema_select, 'The calculations #calculate returns.')

        {
          '$schema' => DIALECT,
          'title' => model.model_name.human.pluralize,
          'type' => 'object',
          'properties' => properties,
          # #index needs a limit when there is no default; #calculate, which
          # takes a select, doesn't
          'anyOf' => ([{ 'required' => ['limit'] }, { 'required' => ['select'] }] if resource_limit && !default_limit),
          '$defs' => (defs.to_h if defs.any?)
        }.compact
      end

      # The $defs of a query schema, with what building them needs to know:
      # the +ref+ query_schema_for was given, the model it was given for, and
      # the includes each name was built for. Each query_schema_for has its
      # own, so one can be built while another is.
      class Defs < Hash
        attr_reader :include_sources

        def initialize(root = nil, ref = nil)
          super()
          @root = root
          @ref = ref
          @include_sources = {}
        end

        # The schema +ref+ gives for the +kind+ of +model+, or nil to build
        # it. The model being described is always built.
        def external_ref(model, kind)
          @ref.call(model, kind) if @ref && model != @root
        end
      end

      private

      # The ACL, read from the controller, where these are private

      # The ACL's wheres for +model+, as name => operators
      def json_schema_wheres(model)
        controller.send(:normalize_where_permit, controller.send(:wheres_for, model))
      end

      def json_schema_orders(model)
        controller.send(:orders_for, model)
      end

      def json_schema_required_orders
        controller.send(:required_orders)
      end

      # The ACL's includes for +model+, normalized
      def json_schema_includes(model)
        controller.send(:normalize_includes, controller.send(:includes_for, model))
      end

      # The key #create and #update read +model+'s params from
      def json_schema_param_key(model)
        controller.model_name(model)
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

      # The JSON Schema of a value of the attribute a definition describes, from
      # its +type+ (json_schema_for_type) and +enum+, and with
      # +validations+ its validations. Not nullable: the caller decides.
      def json_schema_value(model, definition, validations: false)
        schema = json_schema_for_type(definition[:type]).deep_stringify_keys
        json_schema_validations(schema, model, definition) if validations
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
      def json_schema_validations(schema, model, definition)
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

      def json_schema_nullable(schema)
        schema = schema.dup
        schema['enum'] |= [nil] if schema['enum']

        case schema['type']
        when String then schema['type'] = [schema['type'], 'null']
        when Array then schema['type'] = schema['type'] | ['null']
        end
        schema
      end

      # schema/read

      def json_schema_record_read(model, includes)
        if model_partial(model) != 'application/record'
          return {
            'type' => 'object',
            'description' => "Rendered by #{model_partial(model)}"
          }
        end

        properties = json_schema_definitions(model).transform_values do |definition|
          json_schema_attribute_read(model, definition)
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
            { 'type' => 'array', 'items' => json_schema_record_read(association.klass, subincludes) }
          elsif model.validators_on(association.name).any? { |v| v.kind == :presence }
            # A required belongs_to (or a has_one validated for presence)
            json_schema_record_read(association.klass, subincludes)
          else
            json_schema_nullable(json_schema_record_read(association.klass, subincludes))
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
          'description' => json_schema_description(model),
          'type' => 'object',
          'properties' => properties,
          'additionalProperties' => false,
          'required' => (required if required.any?)
        }.compact
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

      # schema/write

      # +path+ holds the models already being described, so an association
      # nested back into one of them isn't described again.
      def json_schema_record_write(model, path, nested: false)
        if controller.respond_to?("filter_#{json_schema_param_key(model)}_params", true)
          return {
            'type' => 'object',
            'description' => "Filtered by #{model.name}ACL#filter"
          }
        end

        properties = {}
        required = []
        # Identifies the nested record to update, so is sent though it isn't
        # one of the ACL's attributes
        properties['id'] = json_schema_attribute_write(model, model.primary_key, permitted: true) if nested && model.primary_key
        definitions = json_schema_definitions(model)

        Array(controller.model_attributes(model)).flatten.each do |entry|
          if entry.is_a?(Hash)
            entry.each do |name, permit|
              properties[name.to_s] = permit == [] ? { 'type' => 'array' } : { 'type' => 'object' }
            end
          else
            name = entry.to_s
            properties[name] = json_schema_attribute_write(model, name)
            required << name if !nested && definitions.dig(name, :required)
          end
        end

        properties.merge!(json_schema_nested_write(model, path + [model]))

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
      # +permitted+ is for an attribute the ACL's +nested+ permits rather
      # than its +attributes+, which the definition has as read only.
      def json_schema_attribute_write(model, name, permitted: false)
        definition = json_schema_definitions(model)[name.to_s]
        return {} if !definition

        schema = json_schema_value(model, definition, validations: true)
        schema = { 'type' => 'array', 'items' => schema } if definition[:array]
        # Only a NOT NULL column can't be null
        schema = json_schema_nullable(schema) if definition[:null] != false

        # For an array these describe the array, not its items
        schema['readOnly'] = true if definition[:read_only] && !permitted
        schema['default'] = definition[:default] if !definition[:default].nil?
        schema['description'] = definition[:comment] if definition[:comment]
        schema
      end

      # Mirrors AccessControlList#filter_model_params
      def json_schema_nested_write(model, path)
        method = "nested_#{json_schema_param_key(model)}_attributes"
        return {} if !controller.respond_to?(method, true)

        controller.send(method).each_with_object({}) do |relation, schemas|
          association = model.reflect_on_association(relation)
          next if !association

          if association.belongs_to?
            schemas[association.foreign_key.to_s] = json_schema_attribute_write(model, association.foreign_key.to_s, permitted: true)
            schemas[association.foreign_type.to_s] = { 'type' => 'string' } if association.polymorphic?
          end
          next if association.polymorphic?

          record = if path.include?(association.klass)
            { 'type' => 'object' }
          else
            json_schema_record_write(association.klass, path, nested: true)
          end

          schemas[association.name.to_s] = if association.collection?
            schemas["#{association.name.to_s.singularize}_ids"] = { 'type' => 'array', 'items' => json_schema_id(association) }
            { 'type' => ['array', 'null'], 'items' => record }
          else
            json_schema_nullable(record)
          end
        end
      end

      # Of a collection, which is never polymorphic
      def json_schema_id(association)
        definition = json_schema_definitions(association.klass)[association.klass.primary_key]
        definition ? json_schema_value(association.klass, definition) : {}
      end

      # schema/query

      def json_schema_name(model, kind)
        "#{model.name.gsub('::', '')}#{kind}"
      end

      # A $ref to +name+ in +defs+, which the block builds the first time. The
      # name is taken before it's built, as what's built may refer back to it.
      def json_schema_ref(defs, name)
        if !defs.key?(name)
          defs[name] = nil
          defs[name] = yield
        end
        { '$ref' => "#/$defs/#{name}" }
      end

      def json_schema_where_ref(model, defs)
        defs.external_ref(model, 'Where') || json_schema_ref(defs, json_schema_name(model, 'Where')) { json_schema_where(model, defs) }
      end

      # Mirrors StandardAPI::Wheres#check_wheres: a Hash of permitted keys, or
      # an Array of them joined by "AND" and "OR".
      def json_schema_where(model, defs)
        permit = json_schema_wheres(model)
        properties = {}
        pattern_properties = {}

        permit.each do |key, operators|
          if model.filters.has_key?(key)
            properties[key] = { 'description' => "The #{key} filter" }
          elsif column = model.columns_hash[key]
            properties[key] = json_schema_column_where(model, column, operators)
            if [:json, :jsonb].include?(column.type)
              pattern_properties["^#{Regexp.escape(key)}\\..+$"] = properties[key]
            end
          elsif association = model.reflect_on_association(key)
            properties[key] = json_schema_association_where(association, defs)

            if association.collection?
              ids_key = "#{key.singularize}_ids"
              ids_permit = json_schema_wheres(association.klass)['id']
              ids_column = association.klass.columns_hash['id']
              if ids_key.sub(/_ids\z/, 's') == key && ids_permit && ids_column
                properties[ids_key] = json_schema_column_where(association.klass, ids_column, ids_permit)
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

        self_ref = { '$ref' => "#/$defs/#{json_schema_name(model, 'Where')}" }
        # A bare value is checked as an `eq` on id, but isn't presented:
        # activerecord-filter can't filter on one from a query string.
        {
          'anyOf' => [
            object,
            { 'type' => 'array', 'items' => { 'anyOf' => [{ 'enum' => ['AND', 'OR'] }, self_ref] } }
          ]
        }
      end

      def json_schema_association_where(association, defs)
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
          json_schema_where_ref(association.klass, defs)
        end

        exists ? { 'anyOf' => [exists, filter] } : filter
      end

      # +operators+ are canonical names, as normalize_where_permit gives them,
      # or :all
      def json_schema_column_where(model, column, operators)
        definition = json_schema_definitions(model)[column.name]
        operators = json_schema_operators(column, definition) if operators == :all
        operators = operators.map(&:to_s)
        value = definition ? json_schema_value(model, definition) : {}
        value = { 'type' => 'array', 'items' => value } if column.array

        # A Hash is read as operators (Wheres#where_operators), so a bare value
        # isn't one: an object, ie. of a json column, is compared with an
        # operator
        bare = if value['type'] == 'object'
          nil
        elsif value.key?('type') || value.key?('enum')
          value
        else
          { 'not' => { 'type' => 'object' } }
        end

        any_of = []
        any_of << bare if bare && operators.include?('eq')
        any_of << { 'type' => ['boolean', 'null'] } if operators.include?('eq')
        any_of << { 'type' => 'array', 'items' => value } if operators.include?('in') && !column.array
        any_of << {
          'type' => 'object',
          'properties' => operators.index_with { |operator| json_schema_operator_value(operator, value) },
          'additionalProperties' => false,
          'minProperties' => 1
        }

        { 'anyOf' => any_of }
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

      # Mirrors StandardAPI::Orders#sanitize_orders: a name, an object of them,
      # or an Array of either. The object is built into +defs+ as +name+
      # followed by "Object"; under a Hash in +permit+, which has no name of
      # its own, it's inline.
      def json_schema_order(permit, model, defs, name = nil)
        permit = Array(permit).flatten
        return nil if permit.empty?

        names = []
        properties = {}

        permit.each do |entry|
          if entry.is_a?(Hash)
            entry.each do |key, subpermit|
              key = key.to_s
              names.concat(Array(subpermit).flatten.map { |column| "#{key}.#{column}" })
              properties[key] = json_schema_order(subpermit, nil, defs) || { 'not' => {} }
            end
            next
          end

          key = entry.to_s
          association = model&.reflect_on_association(key)
          if association && !association.polymorphic?
            columns = Array(json_schema_orders(association.klass)).flatten.reject { |x| x.is_a?(Hash) }
            names.concat(columns.map { |column| "#{key}.#{column}" })
            properties[key] = json_schema_order_ref(association.klass, defs)
          else
            names << key
            properties[key] = json_schema_direction
          end
        end

        object = {
          'type' => 'object',
          'properties' => properties,
          'additionalProperties' => false,
          'minProperties' => 1
        }
        object = json_schema_ref(defs, "#{name}Object") { object } if name
        name_schema = { 'type' => 'string', 'enum' => names }

        {
          'anyOf' => [
            name_schema,
            object,
            { 'type' => 'array', 'items' => { 'anyOf' => [name_schema, object] } }
          ]
        }
      end

      def json_schema_order_ref(model, defs)
        name = json_schema_name(model, 'Order')
        defs.external_ref(model, 'Order') || json_schema_ref(defs, name) do
          json_schema_order(json_schema_orders(model), model, defs, name) || { 'not' => {} }
        end
      end

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

      # Mirrors StandardAPI::Includes#sanitize_includes. +model+ is nil under a
      # polymorphic association, where a +where+ can't be checked.
      #
      # The object is built into +defs+ as +name+, and the includes under it
      # are named after +prefix+. The include of an association has the
      # +options+ (+where+, +order+, +limit+, +distinct+, +distinct_on+,
      # +when+) that apply to included records; the top level has none.
      #
      # The include of a method or a polymorphic association with its own
      # permit is named after the path to it, which can be the name of
      # another include, ie. Account's subject and an AccountSubject model are
      # both "AccountSubjectInclude". They share the name: what the second
      # adds to the first is added to it in +defs+, so it accepts what either
      # does. A property both have is the first's.
      def json_schema_include(permit, model, defs, name:, prefix: name, options: true)
        names = permit.keys.map(&:to_s) - StandardAPI::Controller::RESERVED_INCLUDE_KEYS
        object = { '$ref' => "#/$defs/#{name}" }

        # The name is taken before the include is built, as what's built may
        # refer back to it
        shared = defs[name] ||= { 'type' => 'object', 'properties' => {}, 'additionalProperties' => false }
        sources = defs.include_sources[name] ||= []
        source = [permit, model, options]
        if !sources.include?(source)
          sources << source
          built = json_schema_include_object(permit, model, defs, prefix, options: options)
          shared['properties'].merge!(built['properties']) { |_, existing, _| existing }
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

      def json_schema_include_object(permit, model, defs, prefix, options:)
        properties = {}

        permit.each do |name, subpermit|
          next if StandardAPI::Controller::RESERVED_INCLUDE_KEYS.include?(name.to_s)

          association = model&.reflect_on_association(name)
          sub_name = "#{prefix.to_s.delete_suffix('Include')}#{name.to_s.camelize}Include"
          sub = if association && !association.polymorphic?
            if subpermit.empty?
              json_schema_include_ref(association.klass, defs)
            else
              json_schema_include(subpermit, association.klass, defs, name: sub_name)
            end
          elsif subpermit.present?
            json_schema_include(subpermit, nil, defs, name: sub_name)
          end

          # The +when+ of an include is checked against the model it's on, and
          # the include's schema is shared by every model including it. An
          # include with nothing to include of its own, ie. a method or a
          # polymorphic association permitted by name, still takes a +when+.
          if model
            condition = { 'when' => json_schema_when_ref(model, defs) }
            sub = if sub
              { 'allOf' => [sub, { 'properties' => condition }] }
            else
              { 'type' => 'object', 'properties' => condition, 'additionalProperties' => false }
            end
          end

          included = { 'enum' => [true, 'true'] }
          properties[name.to_s] = sub ? { 'anyOf' => [included, sub] } : included
        end

        if options
          properties['where'] = json_schema_where_ref(model, defs) if model && json_schema_wheres(model).any?
          properties['order'] = json_schema_order_ref(model, defs) if model && Array(json_schema_orders(model)).flatten.any?
          properties['limit'] = { 'type' => 'integer', 'minimum' => 0 }
          properties['distinct'] = { 'type' => 'boolean' }

          # Passed through by #sanitize_includes, but not checked by the ACL
          properties['distinct_on'] = json_schema_unchecked(json_schema_columns, 'Columns to select distinct included records on, passed to `distinct_on`.')
          properties['when'] = {
            'type' => 'object',
            'description' => 'Only include for the including records whose rendered value of each attribute equals the given value. #index only.'
          }
        end

        { 'type' => 'object', 'properties' => properties, 'additionalProperties' => false }
      end

      # A $ref to the +when+ of an include on +model+
      def json_schema_when_ref(model, defs)
        json_schema_ref(defs, json_schema_name(model, 'When')) { json_schema_when(model) }
      end

      # Mirrors StandardAPI::Includes#check_include_when: the attributes of
      # +model+ its ACL wheres permit an +eq+ on, each compared with its value
      # as application/_record renders it
      def json_schema_when(model)
        properties = {}
        json_schema_wheres(model).each do |key, operators|
          next if !model.attribute_names.include?(key)
          next if operators != :all && !operators.include?('eq')

          definition = json_schema_definitions(model)[key]
          properties[key] = definition ? json_schema_attribute_read(model, definition) : {}
        end

        { 'type' => 'object', 'properties' => properties, 'additionalProperties' => false }
      end

      def json_schema_include_ref(model, defs)
        defs.external_ref(model, 'Include') ||
          json_schema_include(json_schema_includes(model), model, defs, name: json_schema_name(model, 'Include'))
      end

      # +schema+, described as a param the ACL doesn't check
      def json_schema_unchecked(schema, description)
        schema.merge('description' => "#{description} Not checked by the ACL.")
      end

      # A column, or columns, as a name or "table.column"
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

    end
  end
end
