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
          if ['where', 'order'].include?(k.to_s) # Where and order are not normalized (sanitation happens in activerecord-filter)
            normalized[k] = case v
            when Hash then v.to_h
            when ActionController::Parameters then v.to_unsafe_h
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
        if permit.has_key?(k) || ['where', 'order'].include?(k.to_s)
          permitted[k] = sanitize(v, permit[k] || {}, true)
        else
          if [:raise, nil].include?(Rails.configuration.try(:action_on_unpermitted_includes))
            raise ActionController::UnpermittedParameters.new([k])
          else
            Rails.logger.try(:warn, "Invalid Include: #{k}")
          end
        end
      end

      permitted
    end

  end
end
