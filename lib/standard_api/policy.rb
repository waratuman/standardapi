require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/hash/keys'

module StandardAPI
  # Declares how a model's attributes and associations are described and
  # rendered. Nest a subclass in the model's controller; StandardAPI::Policies
  # finds it. Like strong parameters, only what it declares is used, so a new
  # column or association stays hidden until it's listed. Types and
  # validations still come from the model.
  #
  #   class PhotosController < ApplicationController
  #     class Policy < StandardAPI::Policy
  #       attributes :id, :created_at, orderable: true
  #       attribute :format
  #       attribute :caption, comment: 'Shown under the photo'
  #       attribute :thumbnail_url, :string
  #       attribute :location, if: :admin?
  #
  #       associations :camera, :properties
  #       association :account, policy: AccountNamePolicy
  #       association :comments, unless: -> { record&.locked? }
  #
  #       attributes_for :account_id do |account_id|
  #         Field.where(account_id: account_id).each do |field|
  #           attribute field.key, field.value_type, comment: field.name
  #         end
  #       end
  #
  #       private
  #
  #       def account_id = record&.account_id
  #     end
  #   end
  #
  # One instance serves a model for the length of a request, on its controller.
  # A method it doesn't define goes to the controller, private ones included.
  class Policy

    # The changes a Policy's declarations make to a model's definitions
    class Builder
      DEFAULTS = {
        name: nil, type: nil, enum: nil, default: nil, primary_key: false,
        null: true, array: false, comment: nil, auto_populated: false,
        read_only: true, required: false, validations: [].freeze
      }.freeze
      OPTIONS = (DEFAULTS.keys - [:name, :type]).freeze
      ASSOCIATION_OPTIONS = [:policy, :types].freeze

      # +association_options+ are each declared association's options,
      # +values+ each attribute's declared +value+, +orderable+ the names of
      # those declared +orderable+, and +filterable_operators+ what's declared
      # +filterable+, as name => :all or the canonical operators it permits,
      # with +filterable_conditions+ those of a standalone +filterable+
      attr_reader :conditions, :association_options, :association_conditions, :values, :orderable,
        :filterable_operators, :filterable_conditions

      def initialize
        @changes = {}
        @conditions = {}
        @values = {}
        @association_options = {}
        @association_conditions = {}
        @orderable = []
        @filterable_operators = {}
        @filterable_conditions = {}
      end

      # Declare the attribute +name+, changing it with +options+, or add it
      # when +type+ is given and the model doesn't have it. +if+ and +unless+
      # hide it per record, and +value+ renders it in place of the record's.
      # +orderable+ lets a request order by it, and +filterable+ filter on it:
      # +true+ with any operator, or only the operators it lists.
      def attribute(name, type = nil, **options)
        name = name.to_s
        conditions = options.extract!(:if, :unless)
        value = options.delete(:value)
        orderable!(name, options.delete(:orderable)) if options.key?(:orderable)
        filterable!(name, options.delete(:filterable)) if options.key?(:filterable)
        unknown = options.keys - OPTIONS
        raise ArgumentError, "unknown options for attribute #{name}: #{unknown.join(', ')}" if !unknown.empty?

        changes = (@changes[name] ||= {})
        changes[:type] = type.to_s if type
        changes.merge!(options)
        (@conditions[name] ||= []).concat(conditions.to_a) if !conditions.empty?
        @values[name] = value if value
        self
      end

      def attributes(*names, **options)
        names.each { |name| attribute(name, **options) }
        self
      end

      # Declare the association +name+, or a method rendered as an include,
      # so a request may include it and it renders. +if+ and +unless+ hide it
      # per record. The included records render with +policy+ in place of
      # their own model's Policy, if it's given. Under a polymorphic
      # association or a method there's no single model to check what's
      # included of it against, so +types+ lists the models it can be, ie.
      # `types: [Property, 'Account']`, and what one of their Policies declares
      # can be included of it. +orderable+ lets a request order by what the
      # associated model's own Policy makes orderable, and +filterable+ filter
      # on what it makes filterable.
      def association(name, **options)
        name = name.to_s
        conditions = options.extract!(:if, :unless)
        orderable!(name, options.delete(:orderable)) if options.key?(:orderable)
        if options.key?(:filterable)
          filterable = options.delete(:filterable)
          if filterable != true && filterable != false
            raise ArgumentError, "association #{name} can only be filterable: true; what can be filtered on it is up to the associated model's Policy"
          end
          filterable!(name, filterable)
        end
        unknown = options.keys - ASSOCIATION_OPTIONS
        raise ArgumentError, "unknown options for association #{name}: #{unknown.join(', ')}" if !unknown.empty?

        (@association_options[name] ||= {}).merge!(options)
        (@association_conditions[name] ||= []).concat(conditions.to_a) if !conditions.empty?
        self
      end

      def associations(*names, **options)
        names.each { |name| association(name, **options) }
        self
      end

      # Let a request filter on +names+ without declaring them, ie. a
      # +filter_on+ filter, a has_and_belongs_to_many join table or an
      # association that isn't included, with any operator, or only
      # +operators+. +if+ and +unless+ are decided for the model.
      def filterable(*names, operators: true, **options)
        conditions = options.extract!(:if, :unless)
        raise ArgumentError, "unknown options for filterable: #{options.keys.join(', ')}" if !options.empty?

        names.map(&:to_s).each do |name|
          filterable!(name, operators)
          conditions.empty? ? @filterable_conditions.delete(name) : (@filterable_conditions[name] = conditions.to_a)
        end
        self
      end

      # Take back a declaration, ie. one inherited from a parent Policy
      def remove(*names)
        names.map(&:to_s).each do |name|
          @changes.delete(name)
          @conditions.delete(name)
          @values.delete(name)
          @association_options.delete(name)
          @association_conditions.delete(name)
          @orderable.delete(name)
          @filterable_operators.delete(name)
          @filterable_conditions.delete(name)
        end
        self
      end

      # New definitions; those in +defaults+ are shared, so aren't changed
      def apply(defaults, model)
        pending = @changes.dup
        definitions = defaults.filter_map do |definition|
          changes = pending.delete(definition[:name])
          definition.merge(changes) if changes
        end

        pending.each do |name, changes|
          # A real attribute the query didn't select can't be read from the record
          next if model.attribute_names.include?(name)

          if !changes[:type]
            raise ArgumentError, "#{model.name} has no attribute #{name}; adding one needs a type"
          end
          definitions << DEFAULTS.merge(name: name).merge(changes)
        end

        definitions
      end

      # The model's attributes these declarations leave out
      def hidden_attributes(model)
        model.attribute_names - @changes.keys
      end

      private

      # +orderable: false+ takes back an inherited one
      def orderable!(name, orderable)
        orderable ? (@orderable |= [name]) : @orderable.delete(name)
      end

      # +filterable: false+ takes back an inherited one; +true+ or "*" permit
      # any operator
      def filterable!(name, filterable)
        if !filterable
          @filterable_operators.delete(name)
          @filterable_conditions.delete(name)
        elsif filterable == true || filterable.to_s == '*'
          @filterable_operators[name] = :all
        else
          @filterable_operators[name] = Array.wrap(filterable).map { |operator| StandardAPI::Wheres.canonical_operator(operator) }
        end
      end
    end

    class_attribute :policy_steps, instance_accessor: false, default: [].freeze

    class << self
      # See Builder#attribute. Conditions may be a Symbol naming a method or a
      # Proc. Both run on the Policy instance, take no arguments and read the
      # record from +record+, which is nil for a model. So does +value+, which
      # is only run for a record.
      def attribute(name, type = nil, **options)
        value = options[:value]
        if value && !value.is_a?(Proc) && !value.is_a?(Symbol)
          raise ArgumentError, "the value of attribute #{name} must be a Symbol or a Proc"
        end

        # A value can read the requester as a condition can
        varies = options.key?(:if) || options.key?(:unless) || !value.nil?
        add_step(varies: varies) { attribute(name, type, **options) }
      end

      def attributes(*names, **options)
        add_step { attributes(*names, **options) }
      end

      # See Builder#association. +policy+ is a Policy class, or a Symbol or
      # Proc run like a condition, on the record including them, that returns
      # one, or nil to render the included records with their own Policy. To
      # keep what their own Policy hides, it inherits from it.
      def association(name, **options)
        policy = options[:policy]
        if policy && !policy.is_a?(Proc) && !policy.is_a?(Symbol) && !(policy.is_a?(Class) && policy < StandardAPI::Policy)
          raise ArgumentError, "the policy of association #{name} must be a subclass of StandardAPI::Policy, a Symbol or a Proc"
        end

        if !Array(options[:types]).all? { |type| type.is_a?(String) || type.is_a?(Class) }
          raise ArgumentError, "the types of association #{name} must be models or their names"
        end

        if options.key?(:filterable) && options[:filterable] != true && options[:filterable] != false
          raise ArgumentError, "association #{name} can only be filterable: true; what can be filtered on it is up to the associated model's Policy"
        end

        varies = options.key?(:if) || options.key?(:unless) || policy.is_a?(Proc) || policy.is_a?(Symbol)
        # The Policy it gives can vary too, and may not be fully declared yet
        varies ||= -> { policy.varies_by_requester? } if policy.is_a?(Class)
        add_step(varies: varies) { association(name, **options) }
      end

      def associations(*names, **options)
        add_step { associations(*names, **options) }
      end

      # See Builder#filterable. It doesn't change what renders, so it can't
      # make the Policy vary by requester.
      def filterable(*names, **options)
        add_step { filterable(*names, **options) }
      end

      def remove(*names)
        add_step { remove(*names) }
      end

      # Declare attributes only known at runtime. +key+ is a Symbol or Proc that
      # reads +record+ (nil for a model), and records with the same result share
      # them: the block runs on the Policy instance once a request per key, is
      # given the key, and declares with +attribute+, +attributes+,
      # +association+, +associations+ and +remove+.
      # +record+ raises in the block, as the result is shared between records.
      def attributes_for(key, &block)
        raise ArgumentError, 'attributes_for needs a block' if !block

        add_step(key: key, varies: true, &block)
      end

      # Whether the definitions could differ by requester, which fragment
      # caching has to know as its keys can't tell requesters apart. Assumed of
      # conditions, values, attributes_for and an association's +policy+ given
      # as a Symbol or Proc, or one that varies; override to say otherwise.
      def varies_by_requester?
        policy_steps.any? { |step| step[:varies].is_a?(Proc) ? step[:varies].call : step[:varies] }
      end

      private

      def add_step(key: nil, varies: false, &block)
        self.policy_steps += [{ key: key, varies: varies, block: block }.freeze]
      end
    end

    attr_reader :controller, :model

    def initialize(controller, model)
      @controller = controller
      @model = model
      @builders = {}
      @applied = {}.compare_by_identity
      @failed = {}.compare_by_identity
      @failed_associations = {}.compare_by_identity
    end

    # The definitions to use for +record+, or nil for a model, from
    # +defaults+, the ones Policies#default_definitions builds. What they leave
    # out is hidden_attributes.
    def definitions(defaults, record)
      builder = builder_for(record)
      definitions = (@applied[builder] ||= {}.compare_by_identity)[defaults] ||=
        builder.apply(defaults, model)

      failed = failed_conditions(record)
      failed.empty? ? definitions : definitions.reject { |definition| failed.include?(definition[:name]) }
    end

    # Names of the attributes +record+ doesn't render for this requester
    def hidden_attributes(record)
      builder_for(record).hidden_attributes(model) + failed_conditions(record)
    end

    # The value of attribute +name+ to render for +record+: its declared
    # +value+, or else the record's own
    def value(record, name)
      value = builder_for(record).values[name.to_s]
      value ? resolve(value, record) : record.send(name)
    end

    # Whether +record+, or a model with nil, renders an include of association
    # +name+ for this requester: it's declared and its conditions pass
    def association?(record, name)
      name = name.to_s
      builder_for(record).association_options.key?(name) && !failed_association_conditions(record).include?(name)
    end

    # What a request may include, as name => { policy:, types: }: each
    # declared association or method, with the Policy class its +policy+
    # gives for a model (a nil record), and the models its +types+ name. +if+
    # and +unless+ don't apply, as they only hide it per record.
    def declared_includes
      @declared_includes ||= builder_for(nil).association_options.to_h do |name, options|
        types = Array(options[:types]).map { |type| type.is_a?(String) ? type.constantize : type }
        [name, { policy: association_policy(nil, name), types: types }]
      end.with_indifferent_access
    end

    # What a request may order by, for a model (a nil record): the names of
    # the attributes and associations declared +orderable+ whose conditions
    # pass. Ordering through an association is checked against its model's
    # own Policy.
    def permitted_orders
      @permitted_orders ||= builder_for(nil).orderable - failed_conditions(nil) - failed_association_conditions(nil)
    end

    # What a request may filter on, for a model (a nil record), as name =>
    # :all or the canonical operators it permits: what's declared
    # +filterable+, unless a condition hides it from the model. Filtering
    # through an association is checked against its model's own Policy.
    def permitted_wheres
      @permitted_wheres ||= begin
        builder = builder_for(nil)
        hidden = failed_conditions(nil) + failed_association_conditions(nil) + failed(builder.filterable_conditions, nil)
        builder.filterable_operators.except(*hidden)
      end
    end

    # The Policy class the records +record+ includes through the association
    # +name+ render with in place of their own model's, or nil
    def association_policy(record, name)
      policy = builder_for(record).association_options.dig(name.to_s, :policy)
      policy.is_a?(Proc) || policy.is_a?(Symbol) ? resolve(policy, record) : policy
    end

    private

    # The record a condition or attributes_for key is being run for, or nil for
    # a model
    def record
      raise ArgumentError, 'record is shared between records in an attributes_for block; use the key it is given' if @declarations

      @record
    end

    def method_missing(name, ...)
      controller.send(name, ...)
    end

    def respond_to_missing?(name, include_private = false)
      controller.respond_to?(name, true) || super
    end

    def attribute(name, type = nil, **options)
      declarations.attribute(name, type, **options)
    end

    def attributes(*names, **options)
      declarations.attributes(*names, **options)
    end

    def association(name, **options)
      declarations.association(name, **options)
    end

    def associations(*names, **options)
      declarations.associations(*names, **options)
    end

    def filterable(*names, **options)
      declarations.filterable(*names, **options)
    end

    def remove(*names)
      declarations.remove(*names)
    end

    def declarations
      @declarations || raise(ArgumentError, 'declare attributes in the class body or an attributes_for block')
    end

    def failed_conditions(record)
      @failed[record] ||= failed(builder_for(record).conditions, record)
    end

    def failed_association_conditions(record)
      @failed_associations[record] ||= failed(builder_for(record).association_conditions, record)
    end

    def failed(conditions, record)
      conditions.filter_map do |name, list|
        name if list.any? { |kind, condition| !!resolve(condition, record) == (kind == :unless) }
      end
    end

    def builder_for(record)
      steps = self.class.policy_steps
      keys = steps.map { |step| resolve(step[:key], record) if step[:key] }

      @builders[keys] ||= begin
        @declarations = Builder.new
        steps.zip(keys) { |step, key| instance_exec(key, &step[:block]) }
        @declarations
      ensure
        @declarations = nil
      end
    end

    def resolve(callable, record)
      previous, @record = @record, record
      callable.is_a?(Proc) ? instance_exec(&callable) : send(callable)
    ensure
      @record = previous
    end

  end
end

require 'standard_api/policy/record'
