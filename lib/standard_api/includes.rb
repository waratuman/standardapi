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
    def sanitize_includes(includes, permit, model, normalized: false)
      includes = normalize_includes(includes) if !normalized
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      if permit.is_a?(Array)
        permit = permit.inject({}) { |acc, v| acc[v] = true; acc }
      end

      permit = normalize_includes(permit.with_indifferent_access)
      includes.each do |k, v|
        permitted[k] = if permit.has_key?(k)
          check_include_when(k, v['when'], model) if v.is_a?(Hash) && v.has_key?('when')

          subpermit = permit[k] || {}
          association = model&.reflect_on_association(k)
          if association && !association.polymorphic?
            subpermit = includes_for(association.klass) if subpermit.empty?
            sanitize_includes(v, subpermit, association.klass, normalized: true)
          else
            sanitize_includes(v, subpermit, nil, normalized: true)
          end
        elsif ['limit', 'when', 'where', 'order', 'distinct', 'distinct_on'].include?(k.to_s)
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
    # the records the include is on. Under a polymorphic association there is
    # no single model to check against; a +when+ there only stops preloading.
    def check_include_when(key, conditions, model)
      return if !model
      raise StandardAPI::UnpermittedParameters.new(["#{key}[when]"]) if !conditions.is_a?(Hash)

      conditions.each_key do |name|
        next if model.attribute_names.include?(name.to_s) || model.attribute_alias?(name)

        raise StandardAPI::UnpermittedParameters.new(["#{key}[when][#{name}]"])
      end
    end

  end
end
