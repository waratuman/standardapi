module StandardAPI
  # Included in StandardAPI::Controller, so the ACL +wheres+ methods are
  # called on the controller.
  module Wheres

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

    # The ACL +wheres+ method for +klass+, falling back to the one for its
    # base class (ie. an STI subclass), or nil if there is none
    def wheres_method_for(klass)
      [klass, klass.base_class].uniq.map { |k| "#{k.model_name.singular}_wheres" }.find do |method|
        self.respond_to?(method, true)
      end
    end

    # The wheres the ACL permits on +klass+, or [] if it has none
    def wheres_for(klass)
      return [] if !(method = wheres_method_for(klass))

      self.send(method)
    end

    # Check +wheres+, ie. the +where+ param, against +permit+, the wheres
    # permitted on +model+, and return them, or raise
    # StandardAPI::UnpermittedParameters.
    #
    # A column (or "*") permits any operator, or the operators it permits can
    # be listed:
    #
    #   sanitize_wheres({ size: { gt: 1 } }, [:name, { size: [:gt, :lt] }], Property)
    #   # => { size: { gt: 1 } }
    #
    # An association permitted by name is checked against the wheres the ACL
    # permits on the associated model. A +filter_on+ filter is permitted by
    # name, and its value is not checked.
    def sanitize_wheres(wheres, permit, model)
      check_wheres(wheres, normalize_where_permit(permit), model)
      wheres
    end

    # { "column" => :all | [canonical operators] }
    def normalize_where_permit(permit)
      permit.each_with_object({}) do |entry, normalized|
        if entry.is_a?(Hash)
          entry.each do |key, operators|
            normalized[key.to_s] = if operators.to_s == '*'
              :all
            else
              Array.wrap(operators).map do |operator|
                OPERATOR_NAMES[operator.to_s] || raise(StandardAPI::InvalidConfiguration, "Unknown where operator #{operator.inspect} for #{key}")
              end
            end
          end
        else
          normalized[entry.to_s] = :all
        end
      end
    end

    def check_wheres(wheres, permit, model)
      case wheres
      when nil
      when Array
        wheres.each do |where|
          check_wheres(where, permit, model) unless where == 'AND' || where == 'OR'
        end
      when Hash, ActionController::Parameters
        wheres.each_pair { |key, value| check_where(key.to_s, value, permit, model) }
      else
        check_where('id', wheres, permit, model)
      end
    end

    # Checks +key+ the way activerecord-filter resolves it: a filter_on
    # filter, a column, an association, then an association's +_ids+, which
    # permitting the association permits. Any other key permitted, ie. a
    # has_and_belongs_to_many join table, is permitted by name.
    def check_where(key, value, permit, model)
      name = key.split('.').first
      permitted = permit.fetch(name) do
        ids_association = key.sub(/_ids\z/, 's') if key.end_with?('_ids')
        permit.fetch(ids_association.to_s) { raise StandardAPI::UnpermittedParameters.new([key]) }
      end

      if model.filters.has_key?(key)
        nil
      elsif column = model.columns_hash[name]
        where_operators(value, column).each do |operator|
          canonical = OPERATOR_NAMES[operator.to_s]
          if !canonical || (permitted != :all && !permitted.include?(canonical))
            raise StandardAPI::UnpermittedParameters.new(["#{key}[#{operator}]"])
          end
        end
      elsif association = model.reflect_on_association(key)
        if permitted != :all
          raise StandardAPI::InvalidConfiguration, "#{model.name} wheres can't permit operators on the association #{key}, permit :#{key} and its wheres in the associated model's wheres"
        end

        check_association_where(key, association, value)
      elsif key.end_with?('_ids') && association = model.reflect_on_association(key.sub(/_ids\z/, 's'))
        check_wheres({ id: value }, normalize_where_permit(wheres_for(association.klass)), association.klass)
      end
    end

    # Checks the wheres on an association against the wheres permitted on
    # the associated model. +true+, +false+ and +nil+ test whether there are
    # associated records, so are not checked further.
    def check_association_where(key, association, value)
      return if [true, false, nil, 'true', 'false'].include?(value)

      klass = if association.polymorphic?
        # activerecord-filter joins the class named by +as+, so it must be a
        # model, and the other wheres are checked against it
        as = value.each_pair.find { |k, _| k.to_s == 'as' }&.last if value.respond_to?(:each_pair)
        klass = as.to_s.safe_constantize if as
        if !klass.is_a?(Class) || !(klass < ::ActiveRecord::Base)
          raise StandardAPI::UnpermittedParameters.new(["#{key}[as]"])
        end

        value = value.to_unsafe_h if value.is_a?(ActionController::Parameters)
        value = value.reject { |k, _| k.to_s == 'as' }
        klass
      else
        association.klass
      end

      check_wheres(value, normalize_where_permit(wheres_for(klass)), klass)
    end

    # The operators a where +value+ on +column+ uses, including the implicit
    # +eq+ and +in+ of a bare value
    def where_operators(value, column)
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
