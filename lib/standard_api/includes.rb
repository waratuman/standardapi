module StandardAPI
  # Included in StandardAPI::Controller, so the ACL +includes+ methods are
  # called on the controller.
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

    # The ACL +includes+ method for +klass+, falling back to the one for its
    # base class (ie. an STI subclass), or nil if there is none
    def includes_method_for(klass)
      [klass, klass.base_class].uniq.map { |k| "#{k.model_name.singular}_includes" }.find do |method|
        self.respond_to?(method, true)
      end
    end

    # The includes the ACL permits on +klass+, or [] if it has none
    def includes_for(klass)
      return [] if !(method = includes_method_for(klass))

      permitted = self.send(method)
      normalize_includes(permitted).each do |name, subincludes|
        next if subincludes.blank? || StandardAPI::Controller::RESERVED_INCLUDE_KEYS.include?(name)

        # A polymorphic association, or a method rendered as an include, has
        # no single ACL to permit its includes in, so they can still be
        # permitted here
        association = klass.reflect_on_association(name)
        next if !association || association.polymorphic?

        raise StandardAPI::InvalidConfiguration, "#{ klass.name }ACL#includes permitting includes of #{ name } is not supported, permit :#{ name } in #{ klass.name }ACL#includes and its includes in #{ association.klass.name }ACL#includes instead"
      end

      permitted || []
    end

    # sanitize_includes({:key => {}}, [:key]) # => {:key => {}}
    # sanitize_includes({:key => {}}, {:key => true}) # => {:key => {}}
    # sanitize_includes({:key => {}}, :value => {}}, [:key]) => # Raises ParseError
    # sanitize_includes({:key => {}}, :value => {}}, {:key => true}) => # Raises ParseError
    # sanitize_includes({:key => {:value => {}}}, {:key => [:value]}) # => {:key => {:value => {}}}
    # sanitize_includes({:key => {:value => {}}}, {:key => {:value => true}}) # => {:key => {:value => {}}}
    # sanitize_includes({:key => {:value => {}}}, [:key]) => # Raises ParseError
    #
    # Includes of +model+ nested in an association permitted by name alone
    # (ie. +:key+) are checked against the includes the ACL permits on the
    # associated model:
    #
    # sanitize_includes({:key => {:value => {}}}, [:key], Model) # => {:key => {:value => {}}} if key_includes includes :value
    #
    # +model+ is nil when there is no single model, ie. through a polymorphic
    # association or a method rendered as an include, in which case includes
    # are checked against +permit+ alone.
    #
    # A method of +model+ permitted with an Array or a Hash, ie.
    # +{ data: [:status] }+ or +{ data: {} }+, takes the params nested in its
    # include as its argument instead of permitting includes nested in it, see
    # #method_include_params. +raw+ is the unnormalized +includes+, which
    # normalizing would mangle the params of.
    def sanitize_includes(includes, permit, model, normalized: false, raw: nil)
      raw = includes if !normalized
      includes = normalize_includes(includes) if !normalized
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      if permit.is_a?(Array)
        permit = permit.inject({}) { |acc, v| acc[v] = true; acc }
      end

      permit = permit.with_indifferent_access
      params_permit = permit.select { |_, v| v.is_a?(Array) || v.is_a?(Hash) }
      permit = normalize_includes(permit)
      includes.each do |k, v|
        permitted[k] = if permit.has_key?(k)
          check_include_when(k, v['when'], model) if v.is_a?(Hash) && v.has_key?('when')

          subpermit = permit[k] || {}
          association = model&.reflect_on_association(k)
          if params_permit.has_key?(k) && model && !association && model.method_defined?(k)
            method_include_params(k, v, raw, model, params_permit[k])
          elsif association && !association.polymorphic?
            subpermit = includes_for(association.klass) if subpermit.empty?
            sanitize_includes(v, subpermit, association.klass, normalized: true, raw: raw_include(raw, k))
          else
            sanitize_includes(v, subpermit, nil, normalized: true, raw: raw_include(raw, k))
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

    # The unnormalized value of the include +key+ in +raw+, or nil.
    def raw_include(raw, key)
      case raw
      when Array
        raw.flatten.filter_map { |r| raw_include(r, key) }.last
      when Hash, ActionController::Parameters
        raw[key] || raw[key.to_s]
      end
    end

    # The sanitized include of a method, permitted in ACL +includes+ with
    # +permit+, an Array or a Hash:
    #
    #   { data: [:status] }   # only status is passed
    #   { data: {} }          # any params are passed
    #
    # The params nested in the include, ie. include[data][status]=inactive, are
    # kept under +params+ for the views to pass to the method, which is called
    # without arguments when there are none.
    #
    # A non-empty +permit+ is a list of the params permitted, written as the
    # arguments of ActionController::Parameters#permit (ie.
    # <tt>[:status, { range: [:gt, :lt] }, { ids: [] }]</tt>), and the params
    # sent are rejected with a StandardAPI::UnpermittedParameters if any is
    # not in it. They are then passed as a Hash with Symbol keys. An empty one
    # permits any, so they are passed as the ActionController::Parameters
    # sent, for the method to permit.
    #
    # The controller can also define +#{model}_include_params(name, params)+
    # (+include_params+ in an ACL), which is called with the params and returns
    # what is passed to the method instead, ie. to cast or rename them. It can
    # raise StandardAPI::UnpermittedParameters to reject them.
    def method_include_params(key, normalized, raw, model, permit)
      return {} if normalized.blank?

      params = raw_include(raw, key)
      return {} if !params.is_a?(Hash) && !params.is_a?(ActionController::Parameters)

      params = ActionController::Parameters.new(params) if params.is_a?(Hash)
      params = permit_include_params(key, params, permit) if !(permit.is_a?(Hash) && permit.empty?)

      hook = [model, model.base_class].uniq.map { |k| "#{k.model_name.singular}_include_params" }.find do |method|
        respond_to?(method, true)
      end
      params = send(hook, key, params) if hook

      params.blank? ? {} : { 'params' => params }
    end

    # +params+ permitted by +permit+, or raises StandardAPI::UnpermittedParameters
    def permit_include_params(key, params, permit)
      permitted = params.permit(*include_params_arguments(permit))
      unpermitted = params.to_unsafe_h.keys - permitted.to_h.keys
      unpermitted = [key] if unpermitted.empty? && permitted.to_h != params.to_unsafe_h

      if !unpermitted.empty?
        raise StandardAPI::UnpermittedParameters.new(unpermitted.map { |name| name == key ? key : "#{key}[#{name}]" })
      end

      permitted
    rescue ActionController::UnpermittedParameters => e
      raise StandardAPI::UnpermittedParameters.new(e.params.map { |name| "#{key}[#{name}]" })
    end

    # The arguments of ActionController::Parameters#permit for an ACL +permit+,
    # ie. { status: true, range: [:gt] } => [:status, { range: [:gt] }]
    def include_params_arguments(permit)
      case permit
      when Array
        permit.flat_map { |p| include_params_arguments(p) }
      when Hash
        permit.flat_map do |name, value|
          case value
          when Array then [{ name.to_sym => include_params_arguments(value) }]
          when Hash then value.empty? ? [name.to_sym] : [{ name.to_sym => include_params_arguments(value) }]
          else [name.to_sym]
          end
        end
      else
        [permit.to_sym]
      end
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
