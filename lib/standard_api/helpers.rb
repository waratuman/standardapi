module StandardAPI
  module Helpers

    def serialize_attribute(json, record, name, type)
      value = record.send(name)

      json.set! name, type == :binary ? value&.unpack1('H*') : value
    end

    def preloadables(record, includes, preload_polymorphic_associations = false)
      preloads = {}
      polymorphic_preloads = {}

      includes.each do |key, value|
        if reflection = record.klass.reflections[key]
          case value
          when true
            preloads[key] = value
          when Hash, ActiveSupport::HashWithIndifferentAccess
            if !value.keys.any? { |x| ['when', 'where', 'limit', 'offset', 'order', 'distinct'].include?(x) }
              if !reflection.polymorphic?
                preloads[key.to_sym] = preloadables_hash(reflection.klass, value)
              elsif preload_polymorphic_associations
                polymorphic_preloads[key.to_sym] = value
              end
            end
          end
        end
      end

      if preloads.present?
        record = record.preload(preloads)
      end

      if polymorphic_preloads.present?
        polymorphic_preloads.each do |assoc, assoc_includes|
          association_types = record.inject({}) do |acc, result|
            association_type = result.send("#{ assoc }_type").constantize
            
            inclds = {}
            assoc_includes.each do |key, incld|
              if incld['when'] && incld['when'].all? { |k, v| result.send(k).as_json == v }
                incld.delete('when')
                inclds[key] = preloadables_hash(association_type, incld)
              end
            end
                        
            acc[association_type] ||= [ [], inclds ]
            acc[association_type][0] << result.send("#{ assoc }_id")
            acc
          end

          association_types.each do |association_type, inclds_ids|
            association_ids = inclds_ids[0]
            inclds = inclds_ids[1]
            association_type.where(id: association_ids).preload(inclds).each do |target|
              association = record.find do |r|
                r["#{ assoc }_type"] == target.class.to_s && r["#{ assoc }_id"] == target.id
              end.association(assoc)
              association.target = target
            end
          end
        end
      end

      record
    end

    def preloadables_hash(klass, iclds)
      preloads = {}

      iclds.each do |key, value|
        if reflection = klass.reflections[key]
          case value
          when true
            preloads[key] = value
          when Hash, ActiveSupport::HashWithIndifferentAccess
            if !value.keys.any? { |x| [ 'when', 'where', 'limit', 'offset', 'order', 'distinct' ].include?(x) }
              if !reflection.polymorphic?
                preloads[key] = preloadables_hash(reflection.klass, value)
              end
            end
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

    def can_cache?(klass, includes)
      cache_columns = ['cached_at'] + cached_at_columns_for_includes(includes)
      if (cache_columns - klass.column_names).empty?
        true
      else
        false
      end
    end

    def cache_key(record, includes)
      timestamp_keys = ['cached_at'] + record.class.column_names.select{|x| x.ends_with? "_cached_at"}
      if includes.empty?
        record.cache_key(*timestamp_keys)
      else
        timestamp = timestamp_keys.map { |attr| record[attr]&.to_time }.compact.max
        "#{record.model_name.cache_key}/#{record.id}-#{digest_hash(sort_hash(includes))}-#{timestamp.utc.to_s(record.cache_timestamp_format)}"
      end
    end

    def can_cache_relation?(record, relation, subincludes)
      return false if record.new_record?
      cache_columns = ["#{relation}_cached_at"] + cached_at_columns_for_includes(subincludes).map {|c| "#{relation}_#{c}"}
      if (cache_columns - record.class.column_names).empty?
        true
      else
        false
      end
    end

    def association_cache_key(record, relation, subincludes)
      timestamp = ["#{relation}_cached_at"] + cached_at_columns_for_includes(subincludes).map {|c| "#{relation}_#{c}"}
      timestamp = (timestamp & record.class.column_names).map! { |col| record.send(col) }
      timestamp = timestamp.max

      return if timestamp.nil?

      case association = record.class.reflect_on_association(relation)
      when ActiveRecord::Reflection::HasManyReflection, ActiveRecord::Reflection::HasAndBelongsToManyReflection, ActiveRecord::Reflection::HasOneReflection, ActiveRecord::Reflection::ThroughReflection
        "#{record.model_name.cache_key}/#{record.id}/#{includes_to_cache_key(relation, subincludes)}-#{timestamp.utc.to_fs(record.cache_timestamp_format)}"
      when ActiveRecord::Reflection::BelongsToReflection
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

    def json_column_type(sql_type)
      case sql_type
      when 'binary', 'bytea'
        'binary'
      when /timestamp(\(\d+\))? without time zone/
        'datetime'
      when 'time without time zone'
        'datetime'
      when 'text'
        'string'
      when 'json'
        'hash'
      when 'smallint', 'bigint', 'integer'
        'integer'
      when 'jsonb'
        'hash'
      when 'inet'
        'string' # TODO: should be inet
      when 'hstore'
        'hash'
      when 'date'
        'datetime'
      when /numeric(\(\d+(,\d+)?\))?/
        'decimal'
      when 'double precision'
        'decimal'
      when 'ltree'
       'string'
      when 'boolean'
        'boolean'
      when 'uuid' # TODO: should be uuid
        'string'
      when /character varying(\(\d+\))?/
        'string'
      when /^geometry/
        'ewkb'
      end
    end

  end
end
