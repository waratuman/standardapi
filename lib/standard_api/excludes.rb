module StandardAPI
  module Excludes

    # :x                            => { x: true }
    # [:x, :y]                      => { x: true, y: true }
    # { x: true, y: true }          => { x: true, y: true }
    # [:x, { y: [:z] }]             => { x: true, y: { z: true } }
    # { y: [:z] }                   => { y: { z: true } }
    # { y: { z: true } }            => { y: { z: true } }
    def self.normalize(excludes)
      normalized = ActiveSupport::HashWithIndifferentAccess.new

      case excludes
      when nil
        # empty
      when Array
        excludes.flatten.compact.each { |v| normalized.merge!(normalize(v)) }
      when Hash, ActionController::Parameters
        excludes.each_pair do |k, v|
          normalized[k] = case v
          when true, 'true' then true
          else
            sub = normalize(v)
            sub.empty? ? true : sub
          end
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
      return normalize(b) if a.nil? || (a.respond_to?(:empty?) && a.empty?)
      return normalize(a) if b.nil? || (b.respond_to?(:empty?) && b.empty?)

      a = normalize(a)
      b = normalize(b)
      result = a.dup

      b.each do |k, v|
        result[k] = if !result.key?(k)
          v
        elsif result[k] == true || v == true
          true
        elsif result[k].is_a?(Hash) && v.is_a?(Hash)
          deep_merge(result[k], v)
        else
          v
        end
      end

      result
    end

  end
end
