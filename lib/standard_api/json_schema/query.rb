module StandardAPI
  module JSONSchema
    # The shape of the params #index and #calculate accept, served at
    # schema/query
    module Query

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

      # The shape of the params #index and #calculate accept for +model+: the
      # +where+, +order+ and +include+ the ACL permits, +limit+, +offset+,
      # +distinct+, the model's columns to +group_by+, and the unchecked
      # +distinct_on+, +join+ and +select+.
      #
      # The where, order and include of each other model reachable through a
      # permitted association are built into $defs. With +ref+, they are left to
      # the caller instead: it is called as `ref.(model, kind)`, +kind+ being
      # "Where", "Order" or "Include", and what it returns is used in place of
      # that model's schema, ie. a $ref to the caller's own URI. Returning nil
      # builds it into $defs as without +ref+.
      #
      #   query_schema_for(Property, ref: ->(model, kind) {
      #     { '$ref' => "standardmcp://schema/#{model.model_name.plural}#/$defs/#{model.name}#{kind}" }
      #   })
      def query_schema_for(model, ref: nil)
        defs = Defs.new(model, ref)
        properties = {}

        properties['where'] = where_ref(model, defs) if normalize_where_permit(wheres_for(model)).any?

        order = order_schema(orders_for(model) | required_orders, model, defs, 'Order')
        properties['order'] = order if order

        include_permit = normalize_includes(includes_for(model))
        if include_permit.any?
          properties['include'] = include_schema(include_permit, model, defs,
            name: 'Include', prefix: schema_name(model, ''), options: false)
        end

        properties['limit'] = {
          'type' => 'integer',
          'minimum' => 0,
          'maximum' => resource_limit,
          'default' => default_limit
        }.compact
        properties['offset'] = { 'type' => 'integer', 'minimum' => 0 }
        properties['distinct'] = { 'type' => 'boolean' }

        # Mirrors Controller#group_by, which only accepts the model's columns
        column_name = { 'type' => 'string', 'enum' => model.column_names }
        properties['group_by'] = {
          'anyOf' => [column_name, { 'type' => 'array', 'items' => column_name }],
          'description' => 'Columns of the model to group by. #calculate returns an object keyed by group.'
        }

        # Used by #resources and #calculate_selects, but not checked by the ACL
        properties['distinct_on'] = unchecked(columns_schema, 'Columns to select distinct rows on, passed to `distinct_on`. Takes precedence over `distinct`.')
        properties['join'] = unchecked(
          { 'type' => 'string', 'enum' => model.reflect_on_all_associations.map { |a| a.name.to_s } },
          'An association to inner join, passed to `joins`.'
        )
        properties['select'] = unchecked(select_schema, 'The calculations #calculate returns.')

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

      def schema_name(model, kind)
        "#{model.name.gsub('::', '')}#{kind}"
      end

      # A $ref to +name+ in +defs+, which the block builds the first time. The
      # name is taken before it's built, as what's built may refer back to it.
      def def_ref(defs, name)
        if !defs.key?(name)
          defs[name] = nil
          defs[name] = yield
        end
        { '$ref' => "#/$defs/#{name}" }
      end

      def where_ref(model, defs)
        defs.external_ref(model, 'Where') || def_ref(defs, schema_name(model, 'Where')) { where_schema(model, defs) }
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

      # Mirrors StandardAPI::Orders#sanitize_orders: a name, an object of them,
      # or an Array of either. The object is built into +defs+ as +name+
      # followed by "Object"; under a Hash in +permit+, which has no name of
      # its own, it's inline.
      def order_schema(permit, model, defs, name = nil)
        permit = Array(permit).flatten
        return nil if permit.empty?

        names = []
        properties = {}

        permit.each do |entry|
          if entry.is_a?(Hash)
            entry.each do |key, subpermit|
              key = key.to_s
              names.concat(Array(subpermit).flatten.map { |column| "#{key}.#{column}" })
              properties[key] = order_schema(subpermit, nil, defs) || { 'not' => {} }
            end
            next
          end

          key = entry.to_s
          association = model&.reflect_on_association(key)
          if association && !association.polymorphic?
            columns = Array(orders_for(association.klass)).flatten.reject { |x| x.is_a?(Hash) }
            names.concat(columns.map { |column| "#{key}.#{column}" })
            properties[key] = order_ref(association.klass, defs)
          else
            names << key
            properties[key] = direction_schema
          end
        end

        object = {
          'type' => 'object',
          'properties' => properties,
          'additionalProperties' => false,
          'minProperties' => 1
        }
        object = def_ref(defs, "#{name}Object") { object } if name
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
        defs.external_ref(model, 'Order') || def_ref(defs, name) do
          order_schema(orders_for(model), model, defs, name) || { 'not' => {} }
        end
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
      # The object is built into +defs+ as +name+, and the includes under it
      # are named after +prefix+. The include of an association has the
      # +options+ (+where+, +order+, +limit+, +distinct+, +distinct_on+,
      # +when+) that apply to included records; the top level has none.
      #
      # The include of an association is named after the path to it, which can
      # be the name of another include, ie. Camera's photo and a CameraPhoto
      # model are both "CameraPhotoInclude". They share the name: what the
      # second adds to the first is added to it in +defs+, so it accepts what
      # either does. A property both have is the first's.
      def include_schema(permit, model, defs, name:, prefix: name, options: true)
        names = permit.keys.map(&:to_s) - StandardAPI::Controller::RESERVED_INCLUDE_KEYS
        object = { '$ref' => "#/$defs/#{name}" }

        # The name is taken before the include is built, as what's built may
        # refer back to it
        shared = defs[name] ||= { 'type' => 'object', 'properties' => {}, 'additionalProperties' => false }
        sources = defs.include_sources[name] ||= []
        source = [permit, model, options]
        if !sources.include?(source)
          sources << source
          built = include_object_schema(permit, model, defs, prefix, options: options)
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
          properties['order'] = order_ref(model, defs) if model && Array(orders_for(model)).flatten.any?
          properties['limit'] = { 'type' => 'integer', 'minimum' => 0 }
          properties['distinct'] = { 'type' => 'boolean' }

          # Passed through by #sanitize_includes, but not checked by the ACL
          properties['distinct_on'] = unchecked(columns_schema, 'Columns to select distinct included records on, passed to `distinct_on`.')
          properties['when'] = {
            'type' => 'object',
            'description' => 'Only include for the including records whose rendered value of each attribute equals the given value. #index only.'
          }
        end

        { 'type' => 'object', 'properties' => properties, 'additionalProperties' => false }
      end

      # A $ref to the +when+ of an include on +model+
      def when_ref(model, defs)
        def_ref(defs, schema_name(model, 'When')) { when_schema(model) }
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
        defs.external_ref(model, 'Include') ||
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

    end
  end
end
