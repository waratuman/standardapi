module StandardAPI
  # Included in StandardAPI::Controller. What can be included is what each
  # model's Policy declares with +association+ and +associations+.
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

    # Checks +includes+ of +model+ against what its Policy declares
    # (Policy#declared_includes), or +policy+, the Policy class an association
    # gives in its place, raising UnpermittedParameters for anything else, and
    # returns them normalized. An association's includes are checked against
    # its model's Policy, or the Policy class its +policy+ gives. Under a
    # polymorphic association or a method there is no single model, so they're
    # checked against that Policy class, or else the Policies of the models
    # the association's +types+ name (#sanitize_typed_includes).
    #
    #   association :photos                     # include[photos][account]: PhotoPolicy declares account?
    #   association :subject, types: [Property] # include[subject][photos]: PropertyPolicy declares photos?
    #
    # +policy+ can also be an Array of the Policies the records can render
    # with, nil being their model's, as an association whose +policy+ gives one
    # per record lists them (Policy#declared_includes): an include is
    # permitted if one of them declares it, as each record renders only what
    # its own declares, while a +where+, +order+ or +when+, which runs in SQL
    # across all of them, has to be permitted by every one.
    def sanitize_includes(includes, model, policy = nil, normalized: false)
      includes = normalize_includes(includes) if !normalized
      policies = policy.is_a?(Array) ? policy : [policy]
      # name => what each Policy that declares it declares of it. None under a
      # polymorphic association without a +policy+.
      declared = Hash.new { |hash, key| hash[key] = [] }
      policies.each do |candidate|
        instance = candidate ? policy_instance(candidate, model) : (model_policy(model) if model)
        instance&.declared_includes&.each { |name, entry| declared[name] << entry }
      end
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      includes.each do |k, v|
        permitted[k] = if declared.key?(k.to_s)
          check_include_when(k, v['when'], model, policies) if v.is_a?(Hash) && v.has_key?('when')

          entries = declared[k.to_s]
          sub_policies = entries.flat_map { |entry| entry[:policies] }.uniq
          association = model&.reflect_on_association(k)
          if association && !association.polymorphic?
            sanitize_includes(v, association.klass, sub_policies, normalized: true)
          elsif entries.all? { |entry| entry[:policy] }
            sanitize_includes(v, nil, sub_policies, normalized: true)
          else
            sanitize_typed_includes(v, entries.flat_map { |entry| entry[:types] }.uniq)
          end
        elsif k.to_s == 'where'
          # Filters the included records, so is checked against the wheres
          # permitted by the Policies they render with: +policy+, or else their
          # model's (StandardAPI::Wheres). Without a model, ie. under a
          # polymorphic association, it can't be checked.
          raise StandardAPI::UnpermittedParameters.new([k]) if !model

          policies.map { |candidate| sanitize_wheres(v, record_policy(model, candidate)) }.first
        elsif k.to_s == 'order'
          # Orders the included records, so is checked against the orders
          # permitted by the Policies they render with: +policy+, or else
          # their model's (StandardAPI::Orders). Without a model, ie. under a
          # polymorphic association, it can't be checked.
          raise StandardAPI::UnpermittedParameters.new([k]) if !model

          policies.map { |candidate| sanitize_orders(v, record_policy(model, candidate)) }.first
        elsif ['limit', 'when', 'distinct', 'distinct_on'].include?(k.to_s)
          v
        else
          raise StandardAPI::UnpermittedParameters.new([k])
        end
      end

      permitted
    end

    # Checks +includes+ under a polymorphic association or a method, whose
    # records can be any of +types+: each include is permitted if one of their
    # Policies declares it, and checked below it against that model, so one
    # request can include what different models declare. Like any include
    # without a model, a +where+ or +order+ is rejected.
    def sanitize_typed_includes(includes, types)
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      includes.each do |k, v|
        if StandardAPI::Controller::RESERVED_INCLUDE_KEYS.include?(k.to_s)
          permitted.merge!(sanitize_includes({ k => v }, nil, normalized: true))
          next
        end

        # A +when+ reads the record including it, which can be of any type,
        # so it isn't checked against one (see #check_include_when)
        if v.is_a?(Hash)
          conditions = v['when']
          v = v.except('when')
        end

        error = nil
        sanitized = types.lazy.filter_map do |type|
          sanitize_includes({ k => v }, type, normalized: true)[k]
        rescue StandardAPI::UnpermittedParameters => e
          error ||= e
          nil
        end.first
        raise(error || StandardAPI::UnpermittedParameters.new([k])) if sanitized.nil?

        sanitized['when'] = conditions if conditions
        permitted[k] = sanitized
      end

      permitted
    end

    # The index views render an include only for the records whose attributes
    # match its +when+, ie. include[photos][when][active]=true, read with
    # read_attribute, so its keys must be attributes of +model+, the model of
    # the records the include is on, and are checked like a where with +eq+
    # against the wheres permitted by the Policy those records render with:
    # +policy+, the Policy class the association that included them gives, or
    # else their model's, or by every one when it's an Array of them (see
    # #sanitize_includes). Under a polymorphic association there is no single
    # model to check against; a +when+ there only stops preloading.
    def check_include_when(key, conditions, model, policy = nil)
      return if !model
      raise StandardAPI::UnpermittedParameters.new(["#{key}[when]"]) if !conditions.is_a?(Hash)

      conditions.each_key do |name|
        if !model.attribute_names.include?(name.to_s) && !model.attribute_alias?(name)
          raise StandardAPI::UnpermittedParameters.new(["#{key}[when][#{name}]"])
        end

        (policy.is_a?(Array) ? policy : [policy]).each do |candidate|
          sanitize_wheres({ name.to_s => true }, record_policy(model, candidate))
        end
      end
    end

  end
end
