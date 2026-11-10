module StandardAPI
  module JSONSchema
    # Values for schema/query (application/query_schema and the
    # application/json_schema partials it renders)
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

      private

      # The ACL's wheres for +model+, as name => operators
      def json_schema_wheres(model)
        model ? normalize_where_permit(wheres_for(model)) : {}
      end

      def json_schema_orders(model)
        model ? Array(orders_for(model)).flatten : []
      end

      # The ACL's includes for +model+, normalized
      def json_schema_includes(model)
        normalize_includes(includes_for(model))
      end

      def json_schema_required_orders
        required_orders
      end

      # The name in $defs of the +kind+ ("Where", "Order", "When" or
      # "Include") of +model+
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

      # +operators+ are canonical names, as normalize_where_permit gives them,
      # or :all
      def json_schema_column_where(model, column, operators)
        definition = json_schema_definitions(model)[column.name]
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
