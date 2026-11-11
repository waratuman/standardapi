module StandardAPI
  # What a record's Schemas don't render, built by Schemas#schema_excludes:
  # `name => true` for an attribute or association left out, and for an
  # association whose records are narrowed, `name => { SCHEMAS => [schema] }`.
  module Excludes

    # The key under which an exclude tree lists the Schemas, from a parent's
    # +association ..., schema:+, that narrow the records it applies to. No
    # attribute can be named it. The records apply them rather than forward
    # them, and the Schemas of two parents are both applied.
    SCHEMAS = '$schemas'.freeze

    # +excludes+ (a Hash, or nil) with indifferent access and without the
    # values that exclude nothing: anything but `true`, a Hash or SCHEMAS'
    # list, and an empty Hash or list
    def self.normalize(excludes)
      normalized = ActiveSupport::HashWithIndifferentAccess.new

      (excludes || {}).each_pair do |key, value|
        value = if key.to_s == SCHEMAS
          Array(value).compact.presence
        elsif value == true
          true
        elsif value.is_a?(Hash)
          normalize(value).presence
        end
        next if value.nil?

        # :x and 'x' are the same key once normalized
        normalized[key] = normalized.key?(key) ? merge_values(normalized[key], value) : value
      end

      normalized
    end

    # Merge two exclude trees. A terminal `true` always wins over a sub-hash,
    # so neither side can un-hide what the other hid, and the Schemas of both
    # narrow.
    def self.deep_merge(a, b)
      return true if a == true || b == true

      result = normalize(a)
      normalize(b).each do |key, value|
        result[key] = result.key?(key) ? merge_values(result[key], value) : value
      end
      result
    end

    def self.merge_values(a, b)
      if a == true || b == true
        true
      elsif a.is_a?(Hash) && b.is_a?(Hash)
        deep_merge(a, b)
      else
        # The Schemas under SCHEMAS
        a | b
      end
    end
    private_class_method :merge_values

  end
end
