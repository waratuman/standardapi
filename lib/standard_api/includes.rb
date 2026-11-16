module StandardAPI
  # Included in StandardAPI::Controller. What can be included is what each
  # model's Schema declares with +association+ and +associations+.
  module Includes

    private

    # :x                            => { x: {} }
    # [:x, :y]                      => { x: {}, y: {} }
    # [ { x: true }, { y: true } ]  => { x: {}, y: {} }
    # { x: true, y: true }          => { x: {}, y: {} }
    # { x: { y: true } }            => { x: { y: {} } }
    # { x: [:y] }                   => { x: { y: {} } }
    # { x: { where: { y: false } } }    => { x: { where: { y: false } } }
    # { x: { order: { y: :asc } } }    => { x: { order: { y: :asc } } }
    def normalize_includes(includes)
      normalized = ActiveSupport::HashWithIndifferentAccess.new

      case includes
      when Array
        includes.flatten.compact.each { |v| normalized.merge!(normalize_includes(v)) }
      when Hash, ActionController::Parameters
        includes.each_pair do |k, v|
          normalized[k] = case k.to_s
          when 'when', 'where', 'order'
            case v
            when Array
              v.map do |x|
                case x
                when Hash then x.to_h
                when ActionController::Parameters then x.to_unsafe_h
                else
                  x
                end
              end
            when Hash then v.to_h
            when ActionController::Parameters then v.to_unsafe_h
            end
          when 'limit'
            case v
            when String then v.to_i
            when Integer then v
            end
          when 'distinct'
            case v
            when 'true' then true
            when 'false' then false
            end
          when 'distinct_on'
            case v
            when String then v
            when Array then v
            end
          else
            normalize_includes(v)
          end
        end
      when nil
        {}
      else
        if ![true, 'true'].include?(includes)
          normalized[includes] = {}
        end
      end

      normalized
    end

    # What a request may include of +model+, from its Schema, or from
    # +schema+, the Schema class an association gives in its place, as
    # name => { schema:, includes: } (Schema#declared_includes). {} when there
    # is neither, ie. under a polymorphic association without a +schema+.
    def includes_for(model, schema = nil)
      instance = schema ? schema_instance(schema, model) : (model_schema(model) if model)
      instance ? instance.declared_includes : {}
    end

    # The +includes+ option of an association, a permit like ACL +includes+
    # once was, as name => { schema: nil, includes: }
    def permitted_includes(permit)
      normalize_includes(permit).except(*StandardAPI::Controller::RESERVED_INCLUDE_KEYS).to_h do |name, sub|
        [name, { schema: nil, includes: sub.presence }]
      end.with_indifferent_access
    end

    # Checks +includes+ of +model+ against what its Schema declares
    # (#includes_for), raising UnpermittedParameters for anything else, and
    # returns them normalized. An association's includes are checked against
    # its model's Schema, or the Schema class its +schema+ gives. Under a
    # polymorphic association or a method there is no single model, so they're
    # checked against that Schema class, or else the association's
    # +includes+ (+permit+).
    #
    #   association :photos                       # include[photos][account]: PhotoSchema declares account?
    #   association :subject, includes: [:photos] # include[subject][photos]
    def sanitize_includes(includes, model, schema = nil, permit: nil, normalized: false)
      includes = normalize_includes(includes) if !normalized
      declared = permit ? permitted_includes(permit) : includes_for(model, schema)
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      includes.each do |k, v|
        permitted[k] = if declared.has_key?(k)
          check_include_when(k, v['when'], model) if v.is_a?(Hash) && v.has_key?('when')

          entry = declared[k]
          association = model&.reflect_on_association(k)
          if association && !association.polymorphic?
            sanitize_includes(v, association.klass, entry[:schema], normalized: true)
          elsif entry[:schema]
            sanitize_includes(v, nil, entry[:schema], normalized: true)
          else
            sanitize_includes(v, nil, permit: entry[:includes] || {}, normalized: true)
          end
        elsif k.to_s == 'where'
          # Filters the included records, so is checked against the wheres
          # permitted on their model (StandardAPI::Wheres). Without a model,
          # ie. under a polymorphic association, it can't be checked.
          raise StandardAPI::UnpermittedParameters.new([k]) if !model

          sanitize_wheres(v, wheres_for(model), model)
        elsif k.to_s == 'order'
          # Orders the included records, so is checked against the orders
          # permitted on their model (StandardAPI::Orders). Without a model,
          # ie. under a polymorphic association, it can't be checked.
          raise StandardAPI::UnpermittedParameters.new([k]) if !model

          sanitize_orders(v, orders_for(model), model)
        elsif ['limit', 'when', 'distinct', 'distinct_on'].include?(k.to_s)
          v
        else
          raise StandardAPI::UnpermittedParameters.new([k])
        end
      end

      permitted
    end

    # The index views render an include only for the records whose attributes
    # match its +when+, ie. include[photos][when][active]=true, read with
    # read_attribute, so its keys must be attributes of +model+, the model of
    # the records the include is on, and are checked like a where with +eq+
    # against the wheres permitted on it. Under a polymorphic association
    # there is no single model to check against; a +when+ there only stops
    # preloading.
    def check_include_when(key, conditions, model)
      return if !model
      raise StandardAPI::UnpermittedParameters.new(["#{key}[when]"]) if !conditions.is_a?(Hash)

      conditions.each_key do |name|
        if !model.attribute_names.include?(name.to_s) && !model.attribute_alias?(name)
          raise StandardAPI::UnpermittedParameters.new(["#{key}[when][#{name}]"])
        end

        check_wheres({ name.to_s => true }, normalize_where_permit(wheres_for(model)), model)
      end
    end

  end
end
