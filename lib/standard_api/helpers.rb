module StandardAPI
  module Helpers
    include StandardAPI::Helpers::JSONSchema

    # Yield the base controller (the topmost class including +owner+), the
    # +const+ nested in it (ie. PhotosController::Policy) and the model's
    # prefix for each controller with one, so Policies can make it available
    # to every controller.
    def self.each_nested(owner, const)
      ActionController::Metal.descendants.each do |controller|
        next if !controller.const_defined?(const, false)

        # Only a controller using StandardAPI has a model; any other
        # controller's constant is none of our business
        base = controller.ancestors.grep(Class).select { |c| c.include?(owner) }.last
        next if !base || !controller.model

        yield base, controller.const_get(const, false), controller.model.model_name.singular
      end
    end

    # The value of attribute +name+ to render for +record+, from the Policy it
    # renders with (Policy#value), so a declared +value+ renders in place of
    # the record's. An override of serialize_attribute should read the value
    # with this.
    def attribute_value(record, name)
      policy = controller.send(:rendering_policy, record) if respond_to?(:controller) && controller.respond_to?(:rendering_policy, true)
      policy ? policy.value(record, name) : record.send(name)
    end

    def serialize_attribute(json, record, name, type)
      value = attribute_value(record, name)

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

    # +policy+ is the Policy class the records of this relation render with in
    # place of their model's (Policy::Record#association_policy). A fragment it
    # renders isn't cached, as its key doesn't include it.
    def can_cache_relation?(record, relation, subincludes, policy = nil)
      return false if record.new_record?
      cache_columns = ["#{relation}_cached_at"] + cached_at_columns_for_includes(subincludes).map {|c| "#{relation}_#{c}"}
      return false if !(cache_columns - record.class.column_names).empty?
      return false if policy

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
    # through a Policy that varies or a row mask. Cache keys are built from
    # record timestamps and the include digest alone, so a fragment this
    # returns false for must never be cached: it would be handed to the next
    # requester unchanged.
    #
    # Returns true outside a StandardAPI controller, where neither mechanism
    # exists.
    def requester_independent?(klass, includes)
      return true if !respond_to?(:policy_varies?)

      !policy_varies?(klass, includes) && !mask_affect?(klass, includes)
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

    # The `type` schema.json reports for an attribute definition. A
    # column keeps its SQL based type, unless a Policy declared another.
    def schema_json_type(model, schema)
      column = model.columns_hash[schema[:name]]
      attribute_type = model.type_for_attribute(schema[:name])
      built = attribute_type.is_a?(::ActiveRecord::Enum::EnumType) ? 'string' : attribute_type.type&.to_s
      return schema[:type] if !column || schema[:type] != built

      attribute_type.is_a?(::ActiveRecord::Enum::EnumType) ? built : json_column_type(column.sql_type)
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

  end
end
