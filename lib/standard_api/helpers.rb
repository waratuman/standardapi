module StandardAPI
  module Helpers

    def serialize_attribute(json, record, name, type)
      value = record.send(name)

      json.set! name, type == :binary ? value&.unpack1('H*') : value
    end

    def preloadables(record, includes)
      preloads = {}

      includes.each do |key, value|
        if reflection = record.klass.reflections[key]
          case value
          when true
            preloads[key] = value
          when Hash, ActiveSupport::HashWithIndifferentAccess
            if !value.keys.any? { |x| ['when', 'where', 'limit', 'offset', 'order', 'distinct'].include?(x) }
               preloads[key.to_sym] = preloadables_hash(value)
            end
          end
        end
      end

      preloads.present? ? record.preload(preloads) : record
    end

    def preloadables_hash(iclds)
      preloads = {}

      iclds.each do |key, value|
        case value
        when true
          preloads[key] = value
        when Hash, ActiveSupport::HashWithIndifferentAccess
          if !value.keys.any? { |x| [ 'when', 'where', 'limit', 'offset', 'order', 'distinct' ].include?(x) }
            preloads[key] = preloadables_hash(value)
          end
        end
      end

      preloads
    end

    def schema_partial(model)
      path = model.model_name.plural

      if lookup_context.exists?("schema", path, true)
        [path, "schema"].join('/')
      else
        'application/schema'
      end
    end

    def model_partial(record)
      if lookup_context.exists?(record.model_name.element, record.model_name.plural, true)
        [record.model_name.plural, record.model_name.element].join('/')
      else
        'application/record'
      end
    end

    # The attributes of +model+ as StandardAPI exposes them. `json_schema.json`
    # is built from this, so code that needs the same information (an MCP tool
    # describing a model, say) can read it directly instead of rendering a
    # schema view and parsing it back.
    #
    # Returns an Array of Hashes, one per attribute in `model.attribute_names`
    # order: the columns, then any attributes declared without one.
    #
    #   name            String   the attribute name
    #   type            String   the ActiveModel type,
    #                            `type_for_attribute(name).type`, so it is the
    #                            same on every adapter and keeps "date", "time"
    #                            and "datetime" apart. "string" for an enum. nil
    #                            for a type that doesn't name itself
    #   enum            Array    the names an enum accepts, or nil if the
    #                            attribute isn't an enum
    #   default         Object   the column default, cast to Ruby. For an enum,
    #                            the name of the default value
    #   primary_key     Boolean
    #   null            Boolean  whether the column allows NULL
    #   array           Boolean  whether the column is an array; "type" is then
    #                            the type of its elements
    #   comment         String   the column comment, or nil
    #   auto_populated  Boolean  whether the database fills the column in
    #                            itself. nil when the adapter can't tell
    #   read_only       Boolean  true when the attribute can't be changed
    #                            through the API: it is missing from the ACL's
    #                            `attributes`, or the model marks it readonly
    #                            (`attr_readonly`)
    #   required        Boolean  true when a create must set it: the column is
    #                            NOT NULL and writable on create (permitted by
    #                            the ACL, not auto populated; an
    #                            `attr_readonly` attribute can be set on
    #                            create), or it has a presence
    #                            validation, or an acceptance validation
    #                            without `allow_nil`
    #   validations     Array    the model's validations of the attribute, as
    #                            `{ kind: :length, options: { maximum: 12 } }`
    #
    # An attribute with no column has nil `default`, `null`, `comment` and
    # `auto_populated`.
    #
    # The ACL is consulted without a record, as `attributes(nil)`, so
    # `read_only` is the model wide answer. If the ACL defines `schemas`, the
    # built definitions are passed through it and its return value is used.
    # Definitions are built once per model and view context.
    def schemas_for(model)
      @schemas_for ||= {}
      @schemas_for[model] ||= begin
        permitted = controller.model_attributes(model)&.map(&:to_s)

        columns = model.columns_hash
        schemas = model.attribute_names.map do |name|
          attribute_schema(model, name, columns[name], permitted)
        end

        controller.model_schemas(model, schemas)
      end
    end

    def attribute_schema(model, name, column, permitted)
      attribute_type = model.type_for_attribute(name)
      enum = model.defined_enums[name] if attribute_type.is_a?(::ActiveRecord::Enum::EnumType)
      default = column_default_value(column, model) if column
      auto_populated = (!!column.auto_populated? if column.respond_to?(:auto_populated?))
      validations = model.validators_on(name).map { |v| { kind: v.kind, options: v.options } }

      # The ACL decides what can be written; an attr_readonly attribute can be
      # set on create but never changed, so it is read only yet can be required
      acl_read_only = !permitted.nil? && permitted.exclude?(name)
      read_only = acl_read_only || model.readonly_attribute?(name)
      writable_on_create = !acl_read_only && !auto_populated

      {
        name: name,
        type: enum ? 'string' : attribute_type.type&.to_s,
        enum: enum&.keys,
        default: enum ? enum.key(default) : default,
        primary_key: name == model.primary_key,
        null: column&.null,
        array: column ? column.array : false,
        comment: column&.comment,
        auto_populated: auto_populated,
        read_only: read_only,
        required: (column&.null == false && writable_on_create) || validations.any? { |v|
          v[:kind] == :presence || (v[:kind] == :acceptance && v[:options][:allow_nil] != true)
        },
        validations: validations
      }
    end
    private :attribute_schema

    # The excludes that apply to +record+ inside a partial: the record's own
    # ACL excludes deep-merged with whatever the parent partial passed down as
    # the `excludes` local.
    #
    # Custom model partials MUST call this and honour the result. StandardAPI
    # enforces excludes in application/_record only; it cannot filter
    # attributes a hand-written partial serializes itself.
    #
    #   excluded = resolve_excludes(photo, local_assigns[:excludes])
    #
    #   json.set! :format, photo.format unless excluded[:format] == true
    #
    #   # forward the sub-tree when rendering a nested record
    #   json.partial! 'application/record', record: photo.account,
    #     includes: includes[:account], excludes: sub_excludes(excluded, :account)
    def resolve_excludes(record, inherited = nil)
      own = respond_to?(:excludes) ? excludes(record) : nil
      StandardAPI::Excludes.deep_merge(own, inherited)
    end

    # The exclude sub-tree to forward for +key+, or nil when there is nothing
    # to forward. Returns nil for a terminal `true` — that case means the key
    # is dropped entirely and should never be rendered.
    def sub_excludes(excluded, key)
      value = excluded[key]
      value.is_a?(Hash) ? value : nil
    end

    # Apply an exclude sub-tree to a plain JSON value.
    #
    # An include can resolve to something that isn't a record — a method
    # returning a Hash or an Array of Hashes — in which case there is no
    # partial to enforce the excludes and the value would otherwise be
    # serialized whole.
    def apply_excludes(value, excluded)
      return value if excluded.blank?

      case value
      when Array
        value.map { |v| apply_excludes(v, excluded) }
      when Hash
        value.each_with_object({}) do |(key, v), result|
          sub = excluded[key]
          next if sub == true

          result[key] = sub.is_a?(Hash) ? apply_excludes(v, sub) : v
        end
      else
        value
      end
    end

    # Drop validation errors belonging to an excluded attribute. An error key
    # names the attribute it came from, and its message usually quotes the
    # value, so serializing the errors untouched hands back exactly what the
    # exclude was hiding. Nested keys like `photos.caption` are matched on
    # their leading segment.
    def reject_excluded_errors(errors, excluded)
      return errors if excluded.blank?

      errors.reject { |attribute, _| excluded[attribute.to_s.split('.').first] == true }
    end

    def can_cache?(klass, includes)
      cache_columns = ['cached_at'] + cached_at_columns_for_includes(includes)
      return false if !(cache_columns - klass.column_names).empty?

      requester_independent?(klass, includes)
    end

    def cache_key(record, includes)
      timestamp_keys = ['cached_at'] + record.class.column_names.select{|x| x.ends_with? "_cached_at"}
      if includes.empty?
        record.cache_key(*timestamp_keys)
      else
        timestamp = timestamp_keys.map { |attr| record[attr]&.to_time }.compact.max
        "#{record.model_name.cache_key}/#{record.id}-#{digest_hash(sort_hash(includes))}-#{timestamp.utc.to_fs(record.cache_timestamp_format)}"
      end
    end

    # +excludes+ is the exclude sub-tree the parent partial is forwarding for
    # this relation, if any. Its presence alone makes the fragment specific to
    # this requester.
    def can_cache_relation?(record, relation, subincludes, excludes = nil)
      return false if record.new_record?
      cache_columns = ["#{relation}_cached_at"] + cached_at_columns_for_includes(subincludes).map {|c| "#{relation}_#{c}"}
      return false if !(cache_columns - record.class.column_names).empty?
      return false if excludes.present?

      association = record.class.reflect_on_association(relation)
      return true if association.nil?

      klass = association.polymorphic? ? record.send(association.foreign_type)&.constantize : association.klass
      return false if klass.nil?

      # Included collections are row filtered through #mask, so which rows land
      # in the fragment depends on who asked for it.
      return false if association.collection? && respond_to?(:masked?) && masked?(klass)

      requester_independent?(klass, subincludes)
    end

    # False when rendering +klass+ with +includes+ could vary by requester,
    # through an ACL exclude rule or a row mask. Cache keys are built from
    # record timestamps and the include digest alone, so a fragment this
    # returns false for must never be cached: it would be handed to the next
    # requester unchanged.
    #
    # Returns true outside a StandardAPI controller, where neither mechanism
    # exists.
    def requester_independent?(klass, includes)
      return true if !respond_to?(:excludes_affect?)

      !excludes_affect?(klass, includes) && !mask_affect?(klass, includes)
    end

    def association_cache_key(record, relation, subincludes)
      timestamp = ["#{relation}_cached_at"] + cached_at_columns_for_includes(subincludes).map {|c| "#{relation}_#{c}"}
      timestamp = (timestamp & record.class.column_names).map! { |col| record.send(col) }
      timestamp = timestamp.max

      case association = record.class.reflect_on_association(relation)
      when ::ActiveRecord::Reflection::HasManyReflection, ::ActiveRecord::Reflection::HasAndBelongsToManyReflection, ::ActiveRecord::Reflection::HasOneReflection, ::ActiveRecord::Reflection::ThroughReflection
        "#{record.model_name.cache_key}/#{record.id}/#{includes_to_cache_key(relation, subincludes)}-#{timestamp.utc.to_fs(record.cache_timestamp_format)}"
      when ::ActiveRecord::Reflection::BelongsToReflection
        klass = association.options[:polymorphic] ? record.send(association.foreign_type).constantize : association.klass
        if subincludes.empty?
          "#{klass.model_name.cache_key}/#{record.send(association.foreign_key)}-#{timestamp.utc.to_fs(klass.cache_timestamp_format)}"
        else
          "#{klass.model_name.cache_key}/#{record.send(association.foreign_key)}/#{digest_hash(sort_hash(subincludes))}-#{timestamp.utc.to_fs(klass.cache_timestamp_format)}"
        end
      else
        raise ArgumentError, 'Unkown association type'
      end
    end

    def cached_at_columns_for_includes(includes)
      includes.select { |k,v| !['when', 'where', 'limit', 'order', 'distinct', 'distinct_on'].include?(k) }.map do |k, v|
        ["#{k}_cached_at"] + cached_at_columns_for_includes(v).map { |v2| "#{k}_#{v2}" }
      end.flatten
    end

    def includes_to_cache_key(relation, subincludes)
      if subincludes.empty?
        relation.to_s
      else
        "#{relation}-#{digest_hash(sort_hash(subincludes))}"
      end
    end

    def sort_hash(hash)
      hash.keys.sort.reduce({}) do |seed, key|
        if seed[key].is_a?(Hash)
          seed[key] = sort_hash(hash[key])
        else
          seed[key] = hash[key]
        end
        seed
      end
    end

    def digest_hash(*hashes)
      hashes.compact!
      hashes.map! { |h| sort_hash(h) }

      digest =  Digest::MD5.new()
      hashes.each do |hash|
        hash.each do |key, value|
          digest << key.to_s
          if value.is_a?(Hash)
            digest << digest_hash(value)
          else
            digest << value.to_s
          end
        end
      end

      digest.hexdigest
    end

    def column_default_value(column, model)
      return nil if column.default.nil?

      cast_type_for_column(column, model).deserialize(column.default)
    end

    # Resolves a column's database cast type across Rails versions. The public
    # API for this has changed repeatedly:
    #   * Rails 7.2 / 8.0 -> connection.lookup_cast_type_from_column(column)
    #   * Rails 8.1       -> column.fetch_cast_type(connection)
    #   * Rails main      -> column.cast_type (public reader again)
    def cast_type_for_column(column, model)
      if column.respond_to?(:fetch_cast_type)
        column.fetch_cast_type(model.connection)
      elsif column.respond_to?(:cast_type)
        column.cast_type
      else
        model.connection.lookup_cast_type_from_column(column)
      end
    end

    def json_column_type(sql_type)
      case sql_type.to_s.downcase
      when 'binary', 'bytea', 'blob'
        'binary'
      when /\Atimestamp(\(\d+\))? without time zone/
        'datetime'
      when 'time', 'time without time zone'
        'datetime'
      when 'text'
        'string'
      when 'json'
        'hash'
      when 'smallint', 'bigint', /\Ainteger(\(\d+\))?$/
        'integer'
      when 'jsonb'
        'hash'
      when 'inet'
        'string' # TODO: should be inet
      when 'hstore'
        'hash'
      when 'date'
        'datetime'
      when /\Adatetime(\(\d+\))?$/
        'datetime'
      when 'float', /\Adecimal(\(\d+(,\d+)?\))?\z/, /\Anumeric(\(\d+(,\d+)?\))?/
        'decimal'
      when 'double precision'
        'decimal'
      when 'ltree'
       'string'
      when 'boolean'
        'boolean'
      when 'uuid' # TODO: should be uuid
        'string'
      when /\A(?:character varying|varchar)(\(\d+\))?$/
        'string'
      when /\Ageometry/
        'ewkb'
      end
    end
    
    # For JSON Schema
    def json_column_schema(sql_type)
      case sql_type.to_s.downcase
      when 'binary', 'bytea', 'blob'
        # TODO contentMediaType correct?
        # contentEncoding?
        # https://json-schema.org/understanding-json-schema/reference/non_json_data
        {type: 'string', contentMediaType: 'application/octet-stream'}
      when 'duration'
        {type: 'string', format: 'duration'}
      when 'text'
        {type: 'string'}
      when 'json', 'jsonb'
        {type: 'object'}
      when 'smallint', 'bigint', /\Ainteger(\(\d+\))?$/
        {type: 'integer'}
      when 'hstore'
        # TODO contentMediaType? or contentEncoding?
        {type: 'object'}
      when 'datetime', 'time', 'time without time zone', /\Adatetime(\(\d+\))?$/, /\Atimestamp(\(\d+\))? without time zone/
        {type: 'string', format: 'date-time'}
      when 'date'
        {type: 'string', format: 'date'}
      when 'double precision', 'float', /\Adecimal(\(\d+(,\d+)?\))?\z/, /\Anumeric(\(\d+(,\d+)?\))?/
        {type: 'number'}
      when 'inet'
        # TODO contentMediaType? or contentEncoding?
        {type: 'string'}
      when 'ltree'
        # TODO contentMediaType? or contentEncoding?
        {type: 'string'}
      when 'boolean'
        {type: 'boolean'}
      when 'uuid'
        {type: 'string', format: 'uuid'}
      when /\A(?:character varying|varchar)(\(\d+\))?$/
        {type: 'string'}
      when /\Ageometry/
        {type: 'string', contentMediaType: 'application/octet-stream'}
      end
    end

    # The JSON Schema for a #schemas_for `type`, or an empty schema for a type
    # it doesn't know
    def json_schema_for_type(type)
      case type
      when 'string', 'text', 'citext', 'inet', 'cidr', 'macaddr', 'ltree'
        {type: 'string'}
      when 'uuid'
        {type: 'string', format: 'uuid'}
      when 'integer'
        {type: 'integer'}
      when 'float', 'decimal', 'money'
        {type: 'number'}
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

  end
end
