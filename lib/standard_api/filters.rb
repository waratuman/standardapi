module StandardAPI
  # Included in StandardAPI::Controller, so the ACL +filters+ methods are
  # called on the controller.
  module Filters

    # Every operator activerecord-filter accepts on a column, as its canonical
    # name => its aliases.
    #
    # TODO: Move to activerecord-filter, ie. ActiveRecord::Filter::OPERATORS,
    # so this list can't drift from the operators it supports.
    OPERATORS = {
      contains:     [],
      contained_by: [],
      eq:           [:equal_to],
      neq:          [:not, :not_equal],
      excludes:     [],
      gt:           [:greater_than],
      gte:          [:gteq, :greater_than_or_equal_to],
      lt:           [:less_than],
      lte:          [:lteq, :less_than_or_equal_to],
      in:           [],
      not_in:       [],
      has_key:      [],
      has_keys:     [],
      has_any_key:  [],
      intersects:   [],
      like:         [],
      ilike:        [],
      overlaps:     [],
      not_overlaps: [],
      ts_match:     [],
      within:       [],
      # Range columns only, unreleased after activerecord-filter 9.0.0
      ends_before:  [],
      ends_by:      [],
      starts_after: [],
      starts_by:    [],
      adjacent_to:  []
    }.freeze

    # Each operator name and alias, as a String => its canonical name
    OPERATOR_NAMES = OPERATORS.each_with_object({}) do |(operator, aliases), names|
      ([operator] + aliases).each { |name| names[name.to_s] = operator }
    end.freeze

    private

    # The filters the ACL permits on +klass+, or nil if it does not define
    # any, in which case filters are not sanitized
    def filters_for(klass)
      return nil if !self.respond_to?("#{klass.model_name.singular}_filters", true)

      self.send("#{klass.model_name.singular}_filters") || []
    end

    # Check +filters+, ie. the +where+ param, against +permit+ and return
    # them, or raise StandardAPI::UnpermittedParameters.
    #
    # Only the keys of +model+ and the operators on its columns are checked.
    # A column (or "*") permits any operator, or the operators it permits can
    # be listed:
    #
    #   sanitize_filters({ size: { gt: 1 } }, [:name, { size: [:gt, :lt] }], Property)
    #   # => { size: { gt: 1 } }
    #
    # A permitted association or custom filter is permitted by name, and what
    # is filtered on it is not checked.
    def sanitize_filters(filters, permit, model)
      check_filters(filters, normalize_filter_permit(permit), model)
      filters
    end

    # { "column" => :all | [canonical operators] }
    def normalize_filter_permit(permit)
      Array.wrap(permit).flatten.each_with_object({}) do |entry, normalized|
        if entry.is_a?(Hash)
          entry.each do |key, operators|
            normalized[key.to_s] = if operators.to_s == '*'
              :all
            else
              Array.wrap(operators).map do |operator|
                OPERATOR_NAMES[operator.to_s] || raise(ArgumentError, "Unknown filter operator #{operator.inspect} for #{key}")
              end
            end
          end
        else
          normalized[entry.to_s] = :all
        end
      end
    end

    def check_filters(filters, permit, model)
      case filters
      when nil
      when Array
        filters.each do |filter|
          check_filters(filter, permit, model) unless filter == 'AND' || filter == 'OR'
        end
      when Hash, ActionController::Parameters
        filters.each { |key, value| check_filter(key.to_s, value, permit, model) }
      else
        check_filter('id', filters, permit, model)
      end
    end

    def check_filter(key, value, permit, model)
      name = key.split('.').first
      permitted = permit.fetch(name) { raise StandardAPI::UnpermittedParameters.new([key]) }

      column = model.columns_hash[name] if !model.filters.has_key?(key)
      return if !column

      filter_operators(value, column).each do |operator|
        canonical = OPERATOR_NAMES[operator.to_s]
        if !canonical || (permitted != :all && !permitted.include?(canonical))
          raise StandardAPI::UnpermittedParameters.new(["#{key}[#{operator}]"])
        end
      end
    end

    # The operators a filter +value+ on +column+ uses, including the implicit
    # +eq+ and +in+ of a bare value
    def filter_operators(value, column)
      case value
      when Hash, ActionController::Parameters
        # An `at` Hash is a relative date/time value, not operators (unreleased
        # after activerecord-filter 9.0.0)
        value.keys.any? { |k| k.to_s == 'at' } ? [:eq] : value.keys
      when Array
        column.try(:array) ? [:eq] : [:in]
      else
        [:eq]
      end
    end

  end
end
