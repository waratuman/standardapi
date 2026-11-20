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
    # returns them normalized. +policy+ can also be an Array of the Policies
    # the records can render with, nil being their model's, as an association
    # whose +policy+ gives one per record lists them. See
    # #sanitize_candidate_includes.
    #
    #   association :photos                     # include[photos][account]: PhotoPolicy declares account?
    #   association :subject, types: [Property] # include[subject][photos]: PropertyPolicy declares photos?
    def sanitize_includes(includes, model, policy = nil, normalized: false)
      includes = normalize_includes(includes) if !normalized
      candidates = (policy.is_a?(Array) ? policy : [policy]).map { |candidate| [model, candidate] }
      sanitize_candidate_includes(includes, candidates)
    end

    # Checks +includes+ of records that can be of more than one model, or
    # render with more than one Policy. +candidates+ are [model, policy]
    # pairs: each model they can be, nil under a polymorphic association or a
    # method with a +policy+, and the Policy class they can render with, nil
    # being their model's own. +polymorphic+ when they're the records of a
    # polymorphic association or a method with +types+.
    #
    # An include is permitted if one of their Policies declares it, as each
    # record renders only what its own Policy declares, and is checked below
    # it against every model and Policy the records it includes can be: those
    # of the association, or the +types+ it names, of each that declares it.
    # Where they can be of different models, ie. the records of an association
    # each type of a polymorphic one has, they're preloaded together, so it
    # has to be declared by every one.
    # A +where+, +order+ or +when+ runs in SQL across all the records, so has
    # to be permitted by every candidate, and is rejected where there's no
    # model to run it on.
    #
    #   association :subject, types: [Account, Property]
    #   # include[subject][owner][where][name]: Account#owner and
    #   # Property#owner are both checked, so it's rejected unless both their
    #   # Policies make name filterable
    def sanitize_candidate_includes(includes, candidates, polymorphic: false)
      # name => [model, what its Policy declares of it], for each declaring it
      declared = Hash.new { |hash, key| hash[key] = [] }
      candidates.each do |model, policy|
        instance = policy ? policy_instance(policy, model) : (model_policy(model) if model)
        instance&.declared_includes&.each { |name, entry| declared[name] << [model, entry] }
      end
      checkable = !polymorphic && candidates.all? { |model, _| model }
      # Records of different models, not under a polymorphic association, are
      # preloaded together, which needs each of them to have what's included
      mixed = !polymorphic && candidates.map(&:first).uniq.size > 1
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      includes.each do |k, v|
        name = k.to_s
        permitted[k] = if declared.key?(name) && (!mixed || declared[name].size == candidates.size)
          # A +when+ reads the records including it, so it's checked against
          # them; under a polymorphic association it only stops preloading
          if checkable && v.is_a?(Hash) && v.has_key?('when')
            candidates.each { |model, policy| check_include_when(k, v['when'], model, policy) }
          end

          sub_polymorphic = false
          sub_candidates = declared[name].flat_map do |model, entry|
            association = model&.reflect_on_association(k)
            if association && !association.polymorphic?
              entry[:policies].map { |policy| [association.klass, policy] }
            elsif entry[:policy]
              entry[:policies].map { |policy| [nil, policy] }
            else
              sub_polymorphic = true
              entry[:types].map { |type| [type, nil] } + entry[:policies].compact.map { |policy| [nil, policy] }
            end
          end.uniq
          sanitize_candidate_includes(v, sub_candidates, polymorphic: sub_polymorphic)
        elsif name == 'where' || name == 'order'
          # Filters or orders the included records, so is checked against the
          # wheres or orders (StandardAPI::Wheres, StandardAPI::Orders)
          # permitted by every Policy they can render with
          raise StandardAPI::UnpermittedParameters.new([k]) if !checkable

          sanitized = candidates.map do |model, policy|
            name == 'where' ? sanitize_wheres(v, record_policy(model, policy)) : sanitize_orders(v, record_policy(model, policy))
          end.uniq
          # An order can normalize differently by model (ie. an attribute in
          # one and an association in another); with no one form for every
          # model, it's rejected
          raise StandardAPI::UnpermittedParameters.new([k]) if sanitized.size > 1

          sanitized.first
        elsif ['limit', 'when', 'distinct', 'distinct_on'].include?(name)
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
    # against the wheres permitted by the Policy those records render with:
    # +policy+, the Policy class the association that included them gives, or
    # else their model's. #sanitize_candidate_includes checks it against every
    # model and Policy they can be, and not under a polymorphic association,
    # where there is no single model to check against; a +when+ there only
    # stops preloading.
    def check_include_when(key, conditions, model, policy = nil)
      return if !model
      raise StandardAPI::UnpermittedParameters.new(["#{key}[when]"]) if !conditions.is_a?(Hash)

      conditions.each_key do |name|
        if !model.attribute_names.include?(name.to_s) && !model.attribute_alias?(name)
          raise StandardAPI::UnpermittedParameters.new(["#{key}[when][#{name}]"])
        end

        sanitize_wheres({ name.to_s => true }, record_policy(model, policy))
      end
    end

  end
end
