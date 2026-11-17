module StandardAPI
  # Included in StandardAPI::Controller. What can be filtered on is what each
  # model's Policy declares +filterable+, record_policy(model).filterable.
  module Wheres

    # The aliases activerecord-filter accepts for an operator, as its
    # canonical name => its aliases, so permitting one permits the others.
    # Other operators aren't checked here: activerecord-filter rejects one it
    # doesn't support.
    #
    # TODO: Move to activerecord-filter, ie. ActiveRecord::Filter, so this
    # list can't drift from the aliases it supports.
    OPERATOR_ALIASES = {
      eq:  [:equal_to],
      neq: [:not, :not_equal],
      gt:  [:greater_than],
      gte: [:gteq, :greater_than_or_equal_to],
      lt:  [:less_than],
      lte: [:lteq, :less_than_or_equal_to]
    }.freeze

    # Each alias, as a String => its canonical name
    CANONICAL_OPERATORS = OPERATOR_ALIASES.each_with_object({}) do |(operator, aliases), names|
      aliases.each { |name| names[name.to_s] = operator.to_s }
    end.freeze

    # The canonical name of the operator +name+, ie. "gt" for "greater_than"
    def self.canonical_operator(name)
      CANONICAL_OPERATORS.fetch(name.to_s, name.to_s)
    end

    private

    # Check +wheres+, ie. the +where+ param, against what +policy+, a
    # Policy::Record, makes filterable on its model, and return them, or raise
    # StandardAPI::UnpermittedParameters.
    #
    # A column permitted with :all permits any operator, or else only the
    # operators listed. If Property's Policy makes +size+ filterable with
    # <tt>[:gt, :lt]</tt>:
    #
    #   sanitize_wheres({ size: { gt: 1 } }, record_policy(Property))
    #   # => { size: { gt: 1 } }
    #
    # An association permitted by name is checked against what the
    # associated model's Policy makes filterable. A +filter_on+ filter is
    # permitted by name, and its value is not checked.
    def sanitize_wheres(wheres, policy)
      check_wheres(wheres, policy)
      wheres
    end

    def check_wheres(wheres, policy)
      case wheres
      when nil
      when Array
        wheres.each do |where|
          check_wheres(where, policy) unless where == 'AND' || where == 'OR'
        end
      when Hash, ActionController::Parameters
        wheres.each_pair { |key, value| check_where(key.to_s, value, policy) }
      else
        check_where('id', wheres, policy)
      end
    end

    # Checks +key+ the way activerecord-filter resolves it: a filter_on
    # filter, a column, an association, then an association's +_ids+, which
    # permitting the association permits. Any other key permitted, ie. a
    # has_and_belongs_to_many join table, is permitted by name.
    def check_where(key, value, policy)
      model = policy.model
      permit = policy.filterable
      name = key.split('.').first
      permitted = permit.fetch(name) do
        ids_association = key.sub(/_ids\z/, 's') if key.end_with?('_ids')
        permit.fetch(ids_association.to_s) { raise StandardAPI::UnpermittedParameters.new([key]) }
      end

      if model.filters.has_key?(key)
        nil
      elsif column = model.columns_hash[name]
        where_operators(value, column).each do |operator|
          next if permitted == :all || permitted.include?(StandardAPI::Wheres.canonical_operator(operator))

          raise StandardAPI::UnpermittedParameters.new(["#{key}[#{operator}]"])
        end
      elsif association = model.reflect_on_association(key)
        if permitted != :all
          raise StandardAPI::InvalidConfiguration, "#{model.name}'s Policy can't permit operators on the association #{key}; make it filterable, and what can be filtered on it filterable in #{association.klass.name}'s Policy"
        end

        check_association_where(key, association, value)
      elsif key.end_with?('_ids') && association = model.reflect_on_association(key.sub(/_ids\z/, 's'))
        check_wheres({ id: value }, record_policy(association.klass))
      end
    end

    # Checks the wheres on an association against what the associated model's
    # Policy makes filterable. +true+, +false+ and +nil+ test whether there are
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

      check_wheres(value, record_policy(klass))
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
