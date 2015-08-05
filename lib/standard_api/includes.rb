require 'active_support/core_ext/hash/indifferent_access'
# require 'active_support/core_ext/hash'
module StandardAPI
  module Includes

    # :x                            => { x: {} }
    # [:x, :y]                      => { x: {}, y: {} }
    # [ { x: true }, { y: true } ]  => { x: {}, y: {} }
    # { x: true, y: true }          => { x: {}, y: {} }
    # { x: { y: true } }            => { x: { y: {} } }
    # { x: [:y] }                   => { x: { y: {} } }
    def self.normalize(includes)
      normalized = ActiveSupport::HashWithIndifferentAccess.new

      case includes
      when Array
        includes.flatten.compact.each { |v| normalized.merge!(normalize(v)) }
      when Hash
        includes.each_pair { |k, v| normalized[k] = normalize(v) }
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
    def self.sanitize(includes, permit)
      includes = normalize(includes)
      permitted = ActiveSupport::HashWithIndifferentAccess.new

      if permit.is_a?(Array)
        permit = permit.inject({}) { |acc, v| acc[v] = true; acc }
      end

      permit = normalize(permit.with_indifferent_access)
      includes.each do |k, v|
        if permit.has_key?(k) || ['where', 'order'].include?(k.to_s)
          permitted[k] = sanitize(v, permit[k] || {})
        else
          if [:raise, nil].include?(Rails.configuration.try(:action_on_unpermitted_includes))
            raise(ActionDispatch::ParamsParser::ParseError.new(<<-ERR.squish, nil))
              Invalid Include: #{k}"
              Set config.action_on_unpermitted_includes = :warm to log instead of raise
            ERR
          else
            Rails.logger.try(:warn, "Invalid Include: #{k}")
          end
        end
      end

      permitted
    end

  end
end