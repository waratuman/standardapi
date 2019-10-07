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
          case k.to_s
          when 'when', 'where', 'order'
            normalized[k] = case v
            when Hash then v.to_h
            when ActionController::Parameters then v.to_unsafe_h
            end
          when 'limit'
            normalized[k] = case v
            when String then v.to_i
            when Integer then v
            end
          when 'distinct'
            normalized[k] = case v
            when 'true' then true
            when 'false' then false
            end
          when 'distinct_on'
            normalized[k] = case v
            when String then v
            when Array then v
            end
          else
            normalized[k] = normalize(v)
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
    def self.sanitize(includes, permit, normalized=false)
      includes = normalize(includes) if !normalized
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      if permit.is_a?(Array)
        permit = permit.inject({}) { |acc, v| acc[v] = true; acc }
      end

      permit = normalize(permit.with_indifferent_access)
      includes.each do |k, v|
        if permit.has_key?(k)
          permitted[k] = sanitize(v, permit[k] || {}, true)
        elsif ['limit', 'when', 'where', 'order', 'distinct', 'distinct_on'].include?(k.to_s)
          permitted[k] = v
        else
          raise StandardAPI::UnpermittedParameters.new([k])
        end
      end

      permitted
    end

  end
end
