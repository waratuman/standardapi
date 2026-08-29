module StandardAPI
  module Excludes

    # :x                            => { x: true }
    # [:x, :y]                      => { x: true, y: true }
    # { x: true, y: true }          => { x: true, y: true }
    # [:x, { y: [:z] }]             => { x: true, y: { z: true } }
    # { y: [:z] }                   => { y: { z: true } }
    # { y: { z: true } }            => { y: { z: true } }
    # { x: false, y: nil, z: [] }   => {}
    #
    # Only `true` excludes a whole key; falsy and empty values exclude nothing.
    def self.normalize(excludes)
      normalized = ActiveSupport::HashWithIndifferentAccess.new

      case excludes
      when nil
        # empty
      when Array
        excludes.flatten.compact.each { |v| normalized = deep_merge(normalized, v) }
      when Hash, ActionController::Parameters
        excludes.each_pair do |k, v|
          value = case v
          when true, 'true' then true
          # A falsy or empty value means "nothing to exclude here". Without
          # this an ACL written as `result[:make] = record.hidden?` would hide
          # `make` on exactly the records it meant to show.
          when false, 'false', nil then nil
          else
            sub = normalize(v)
            sub.empty? ? nil : sub
          end
          next if value.nil?

          # Keys can collide even within one hash, since `:x` and `'x'` are the
          # same key once normalized. Merge rather than overwrite so an earlier
          # exclusion is never silently dropped.
          normalized[k] = normalized.key?(k) ? merge_values(normalized[k], value) : value
        end
      when Symbol, String
        normalized[excludes] = true
      end

      normalized
    end

    # Deep-merge two normalized exclude hashes. A terminal `true` always wins
    # over a sub-hash, so a child ACL cannot un-hide an attribute that a parent
    # decided to hide, and vice versa.
    def self.deep_merge(a, b)
      return true if a == true || b == true
      return normalize(b) if a.nil? || (a.respond_to?(:empty?) && a.empty?)
      return normalize(a) if b.nil? || (b.respond_to?(:empty?) && b.empty?)

      a = normalize(a)
      b = normalize(b)
      result = a.dup

      b.each do |k, v|
        result[k] = result.key?(k) ? merge_values(result[k], v) : v
      end

      result
    end

    # Combine two values held under the same exclude key. A terminal `true`
    # wins over a sub-hash, so neither side can un-hide what the other hid.
    def self.merge_values(a, b)
      if a == true || b == true
        true
      elsif a.is_a?(Hash) && b.is_a?(Hash)
        deep_merge(a, b)
      else
        b
      end
    end
    private_class_method :merge_values

  end
end
