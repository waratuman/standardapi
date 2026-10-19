module StandardAPI
  module Includes

    # :x                            => { x: {} }
    # [:x, :y]                      => { x: {}, y: {} }
    # [ { x: true }, { y: true } ]  => { x: {}, y: {} }
    # { x: true, y: true }          => { x: {}, y: {} }
    # { x: { y: true } }            => { x: { y: {} } }
    # { x: [:y] }                   => { x: { y: {} } }
    # { x: { where: { y: false } } }    => { x: { where: { y: false } } }
    # { x: { order: { y: :asc } } }    => { x: { order: { y: :asc } } }
    def self.normalize(includes)
      normalized = ActiveSupport::HashWithIndifferentAccess.new

      case includes
      when Array
        includes.flatten.compact.each { |v| normalized.merge!(normalize(v)) }
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
            normalize(v)
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

    # sanitize({:key => {}}, [:key]) # => {:key => {}}
    # sanitize({:key => {}}, {:key => true}) # => {:key => {}}
    # sanitize({:key => {}}, :value => {}}, [:key]) => # Raises ParseError
    # sanitize({:key => {}}, :value => {}}, {:key => true}) => # Raises ParseError
    # sanitize({:key => {:value => {}}}, {:key => [:value]}) # => {:key => {:value => {}}}
    # sanitize({:key => {:value => {}}}, {:key => {:value => true}}) # => {:key => {:value => {}}}
    # sanitize({:key => {:value => {}}}, [:key]) => # Raises ParseError
    #
    # When +model+ and a block are given, includes nested in an association
    # permitted by name alone (ie. +:key+) are checked against the associated
    # model's permitted includes, which the block returns for a given model:
    #
    # sanitize({:key => {:value => {}}}, [:key], model: Model) { |m| [:value] } # => {:key => {:value => {}}}
    def self.sanitize(includes, permit, normalized=false, model: nil, &acl)
      includes = normalize(includes) if !normalized
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      if permit.is_a?(Array)
        permit = permit.inject({}) { |acc, v| acc[v] = true; acc }
      end

      permit = normalize(permit.with_indifferent_access)
      includes.each do |k, v|
        permitted[k] = if permit.has_key?(k)
          subpermit = permit[k] || {}
          association = model.reflect_on_association(k) if acl && model
          if association && !association.polymorphic?
            subpermit = acl.call(association.klass) || {} if subpermit.empty?
            sanitize(v, subpermit, true, model: association.klass, &acl)
          else
            sanitize(v, subpermit, true)
          end
        elsif ['limit', 'when', 'where', 'order', 'distinct', 'distinct_on'].include?(k.to_s)
          v
        else
          raise StandardAPI::UnpermittedParameters.new([k])
        end
      end

      permitted
    end

  end
end
