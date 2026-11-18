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
      WRITABLE_OPTIONS = [:on, :permit, :policy].freeze
      ASSIGN_OPTIONS = [:on, :with].freeze

      # +writable+, as standalone +writable+ takes it, as { on:, permit:,
      # policy: }, or nil when it's false. +permit+ is for an attribute and
      # +policy+ for an association, which it can't tell apart without the
      # model. Raises ArgumentError if it's invalid.
      def self.writable_options(name, writable)
        options = case writable
        when nil, false then return nil
        when true then {}
        when Array then { permit: writable }
        when Hash then writable
        else raise ArgumentError, "#{name} can only be writable: true, false, a strong parameters permit Array, or a Hash of options"
        end

        unknown = options.keys - WRITABLE_OPTIONS
        raise ArgumentError, "unknown writable options for #{name}: #{unknown.join(', ')}" if !unknown.empty?
        if ![nil, :create, :update].include?(options[:on])
          raise ArgumentError, "#{name} can only be writable on: :create or :update"
        end
        if options.key?(:policy) && !(options[:policy].is_a?(Class) && options[:policy] < StandardAPI::Policy)
          raise ArgumentError, "the writable policy of #{name} must be a subclass of StandardAPI::Policy"
        end

        options.freeze
      end

      # +options+, as +assign+ takes them: { on:, with: }. Raises
      # ArgumentError if they're invalid.
      def self.assign_options(name, options)
        unknown = options.keys - ASSIGN_OPTIONS
        raise ArgumentError, "unknown assign options for #{name}: #{unknown.join(', ')}" if !unknown.empty?
        if !options[:with].is_a?(Symbol) && !options[:with].is_a?(Proc)
          raise ArgumentError, "assign #{name} needs with:, a Symbol or a Proc"
        end
        if ![nil, :create, :update].include?(options[:on])
          raise ArgumentError, "#{name} can only be assigned on: :create or :update"
        end

        options.freeze
      end

      # +writable+, as +attribute+ takes it: { on:, permit: }
      def self.attribute_writable_options(name, writable)
        options = writable_options(name, writable)
        raise ArgumentError, "attribute #{name} can't be writable with policy:; that's for an association" if options&.key?(:policy)

        options
      end

      # +writable+, as +association+ takes it: { on:, policy: }. What the
      # associated records take is up to their own model's Policy, or
      # +policy+ in its place, so it can't take +permit+.
      def self.association_writable_options(name, writable)
        options = writable_options(name, writable)
        if options&.key?(:permit) || writable.is_a?(Array)
          raise ArgumentError, "association #{name} can only be writable: true, false or { on:, policy: }; what can be written of it is up to the associated model's Policy"
        end

        options
      end

      # +association_options+ are each declared association's options,
      # +values+ each attribute's declared +value+, +orderable+ the names of
      # those declared +orderable+, +required+ those of +required_orders+ in
      # order, +filterable_operators+ what's declared +filterable+, as
      # name => :all or the canonical operators it permits, with
      # +filterable_conditions+ those of a standalone +filterable+,
      # +writable_attributes+ what's declared +writable+, as name =>
      # { on:, permit: }, and +assigned_attributes+ what's declared with
      # +assign+, as name => { on:, with: }
      attr_reader :conditions, :association_options, :association_conditions, :values, :orderable,
        :required, :filterable_operators, :filterable_conditions, :writable_attributes,
        :assigned_attributes

      def initialize
        @changes = {}
        @conditions = {}
        @values = {}
        @association_options = {}
        @association_conditions = {}
        @orderable = []
        @required = []
        @filterable_operators = {}
        @filterable_conditions = {}
        @writable_attributes = {}
        @assigned_attributes = {}
      end

      # Declare the attribute +name+, changing it with +options+, or add it
      # when +type+ is given and the model doesn't have it. +if+ and +unless+
      # hide it per record, and +value+ renders it in place of the record's.
      # +orderable+ lets a request order by it, and +filterable+ filter on it:
      # +true+ with any operator, or only the operators it lists. +writable+
      # lets a create or update set it, see #writable.
      def attribute(name, type = nil, **options)
        name = name.to_s
        conditions = options.extract!(:if, :unless)
        value = options.delete(:value)
        orderable!(name, options.delete(:orderable)) if options.key?(:orderable)
        filterable!(name, options.delete(:filterable)) if options.key?(:filterable)
        if options.key?(:writable)
          writable = options.delete(:writable)
          Builder.attribute_writable_options(name, writable)
          writable!(name, writable)
        end
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
      # on what it makes filterable. +writable+ lets a create or update write
      # it through nested attributes, see #writable: what's written of the
      # associated records is up to their own model's Policy, or the one
      # <tt>writable: { policy: }</tt> gives. An association that renders with
      # +policy+ has to give one, so writes don't use a Policy by accident.
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
        if options.key?(:writable)
          writable = options.delete(:writable)
          Builder.association_writable_options(name, writable)
          writable!(name, writable)
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

      # Order every request by +names+ after what it orders by, ie. +:id+ so
      # pages are stable, unless it already orders by them. They're orderable
      # too, without being declared.
      def required_orders(*names)
        names = names.map(&:to_s)
        @required |= names
        @orderable |= names
        self
      end

      # Let a create or update set +names+ without declaring them, so they
      # aren't rendered, ie. a password or an attr_accessor. What each takes
      # is what its column's type does: a scalar, an array for an array
      # column, or a hash or null for a json one. +permit+ gives it as strong
      # parameters do instead, ie. <tt>[:name, { filter: {} }]</tt> for an
      # array of objects. +on+ is +:create+ or +:update+ to permit it only on
      # one; a model, ie. for the schema, is a create. An association is
      # written through nested attributes, as with
      # <tt>association name, writable: true</tt>, so takes +policy+ in place
      # of +permit+.
      def writable(*names, **options)
        options = Builder.writable_options(names.first, options) || {}
        names.map(&:to_s).each { |name| @writable_attributes[name] = options }
        self
      end

      # Set +names+ on a create or update to what +with+ gives, in place of
      # anything the params send, whether or not they're +writable+. +on+ is
      # +:create+ or +:update+ to set them only on one; a new record is a
      # create.
      def assign(*names, **options)
        options = Builder.assign_options(names.first, options)
        names.map(&:to_s).each { |name| @assigned_attributes[name] = options }
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
          @required.delete(name)
          @filterable_operators.delete(name)
          @filterable_conditions.delete(name)
          @writable_attributes.delete(name)
          @assigned_attributes.delete(name)
        end
        self
      end

      # New definitions; those in +defaults+ are shared, so aren't changed
      def apply(defaults, model)
        pending = @changes.dup
        definitions = defaults.filter_map do |definition|
          changes = pending.delete(definition[:name])
          writable_definition(definition.merge(changes), changes, model) if changes
        end

        pending.each do |name, changes|
          # A real attribute the query didn't select can't be read from the record
          next if model.attribute_names.include?(name)

          if !changes[:type]
            raise ArgumentError, "#{model.name} has no attribute #{name}; adding one needs a type"
          end
          definitions << writable_definition(DEFAULTS.merge(name: name).merge(changes), changes, model)
        end

        definitions
      end

      # The model's attributes these declarations leave out
      def hidden_attributes(model)
        model.attribute_names - @changes.keys
      end

      private

      # A writable attribute can be changed, unless only on create or the
      # model makes it attr_readonly, and a create must set it when it's NOT
      # NULL and not auto populated, unless declared otherwise
      def writable_definition(definition, changes, model)
        writable = @writable_attributes[definition[:name]]
        return definition if !writable

        name = definition[:name]
        definition.merge(
          read_only: changes.fetch(:read_only) { writable[:on] == :create || model.readonly_attribute?(name) },
          required: changes.fetch(:required) do
            definition[:required] ||
              (writable[:on] != :update && definition[:null] == false && !definition[:auto_populated])
          end
        )
      end

      # +writable: false+ takes back an inherited one
      def writable!(name, writable)
        options = Builder.writable_options(name, writable)
        options ? (@writable_attributes[name] = options) : @writable_attributes.delete(name)
      end

      # +orderable: false+ takes back an inherited one, required or not
      def orderable!(name, orderable)
        if orderable
          @orderable |= [name]
        else
          @orderable.delete(name)
          @required.delete(name)
        end
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
        Builder.attribute_writable_options(name, options[:writable])

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
        writable = Builder.association_writable_options(name, options[:writable])
        if writable && options[:policy] && !writable.key?(:policy)
          raise ArgumentError, Policy.writable_policy_message(name)
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

      # See Builder#required_orders. Like +filterable+, it can't make the
      # Policy vary by requester.
      def required_orders(*names)
        add_step { required_orders(*names) }
      end

      # See Builder#writable. It doesn't change what renders either.
      def writable(*names, **options)
        Builder.writable_options(names.first, options)
        add_step { writable(*names, **options) }
      end

      # See Builder#assign. +with+ is a Symbol naming a method or a Proc, run
      # like a condition, for the record being written. It doesn't change
      # what renders either.
      def assign(*names, **options)
        Builder.assign_options(names.first, options)
        add_step { assign(*names, **options) }
      end

      def remove(*names)
        add_step { remove(*names) }
      end

      # Declare attributes only known at runtime. +key+ is a Symbol or Proc that
      # reads +record+ (nil for a model), and records with the same result share
      # them: the block runs on the Policy instance once a request per key, is
      # given the key, and declares with +attribute+, +attributes+,
      # +association+, +associations+, +filterable+, +required_orders+,
      # +writable+, +assign+ and +remove+.
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

    # What every request is ordered by after its own orders, for a model (a
    # nil record): the names declared +required_orders+, in order, unless a
    # condition hides them from the model
    def permitted_required_orders
      @permitted_required_orders ||= builder_for(nil).required - failed_conditions(nil) - failed_association_conditions(nil)
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

    # What a create or update of +record+ may set, a model (nil) being a
    # create, as strong parameters permit them: what's declared +writable+,
    # on that action. It's asked before the params are assigned, so +if+ and
    # +unless+, which decide what renders, don't apply.
    def permitted_attributes(record)
      writable_for(record).flat_map do |name, options|
        next [] if model.reflect_on_association(name)
        if options.key?(:policy)
          raise ArgumentError, "#{name} of #{model.name} isn't an association, so can't be writable with policy:"
        end

        if options.key?(:permit)
          [{ name => options[:permit] }]
        elsif model.columns_hash[name]&.array
          [{ name => [] }]
        elsif [:json, :jsonb].include?(model.type_for_attribute(name).type)
          [name, { name => {} }]
        else
          [name]
        end
      end
    end

    # The names of the associations a create or update of +record+ may write
    # through nested attributes, a model (nil) being a create: those declared
    # +writable+, on that action, or on +on+ when it's given. As with
    # #permitted_attributes, +if+ and +unless+ don't apply. What's written of
    # the associated records is up to their own model's Policy.
    def permitted_associations(record, on: nil)
      builder = builder_for(record)
      writable_for(record, on: on).filter_map do |name, options|
        next if !model.reflect_on_association(name)
        if options.key?(:permit)
          raise ArgumentError, "association #{name} of #{model.name} can't be writable with permit:; what can be written of it is up to the associated model's Policy"
        end
        # Declared apart, ie. policy: in one association and writable: in another
        if !builder.association_options.dig(name, :policy).nil? && !options.key?(:policy)
          raise ArgumentError, Policy.writable_policy_message(name, model)
        end

        name
      end
    end

    # What a create or update of +record+ sets, a model (nil) being a
    # create, as name => value: what's declared with +assign+ on that
    # action, each +with+ run for +record+. It overrides the params.
    def assigned_attributes(record)
      assigned_for(record).to_h { |name, options| [name, resolve(options[:with], record)] }
    end

    # The names #assigned_attributes sets for +record+, without running
    # their +with+
    def assigned_attribute_names(record)
      assigned_for(record).keys
    end

    # The Policy class the records +record+ writes through the association
    # +name+ are written with in place of their own model's, as
    # <tt>writable: { policy: }</tt> gives it, or nil
    def writable_policy(record, name)
      builder_for(record).writable_attributes.dig(name.to_s, :policy)
    end

    # Why an association that renders with +policy+ needs a writable +policy+
    def self.writable_policy_message(name, model = nil)
      of = model ? " of #{model.name}" : ''
      "association #{name}#{of} renders with policy:, so say which Policy writes it with writable: { policy: }, ie. its own model's or the same one"
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

    def required_orders(*names)
      declarations.required_orders(*names)
    end

    def writable(*names, **options)
      declarations.writable(*names, **options)
    end

    def assign(*names, **options)
      declarations.assign(*names, **options)
    end

    def remove(*names)
      declarations.remove(*names)
    end

    def declarations
      @declarations || raise(ArgumentError, 'declare attributes in the class body or an attributes_for block')
    end

    # What's declared +writable+ for +record+, less what's only writable on
    # the other action
    def writable_for(record, on: nil)
      on ||= action_for(record)
      builder_for(record).writable_attributes.reject { |_, options| options[:on] && options[:on] != on }
    end

    # What's declared with +assign+ for +record+, less what's only assigned
    # on the other action. Raises ArgumentError for a name the model can't
    # set, or one it makes attr_readonly that isn't only assigned on create.
    def assigned_for(record)
      on = action_for(record)
      builder_for(record).assigned_attributes.reject do |name, options|
        if !model.attribute_names.include?(name) && !model.method_defined?("#{name}=")
          raise ArgumentError, "#{model.name} has no attribute #{name} to assign"
        end
        if options[:on] != :create && model.readonly_attribute?(name)
          raise ArgumentError, "#{name} of #{model.name} is attr_readonly, so can only be assigned on: :create"
        end

        options[:on] && options[:on] != on
      end
    end

    def action_for(record)
      record.nil? || record.new_record? ? :create : :update
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
