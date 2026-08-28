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
    def can_cache_relation?(record, relation, subincludes, excludes: nil)
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

  end
end
