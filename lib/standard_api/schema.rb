require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/hash/keys'

module StandardAPI
  # Declares how a model's attributes and associations are described and
  # rendered. Nest a subclass in the model's controller; StandardAPI::Schemas
  # finds it. Like strong parameters, only what it declares is used, so a new
  # column or association stays hidden until it's listed. Types and
  # validations still come from the model.
  #
  #   class PhotosController < ApplicationController
  #     class Schema < StandardAPI::Schema
  #       attributes :id, :format, :created_at
  #       attribute :caption, comment: 'Shown under the photo'
  #       attribute :thumbnail_url, :string
  #       attribute :location, if: :admin?
  #
  #       associations :camera, :properties
  #       association :account, schema: AccountNameSchema
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
  class Schema

    # The changes a Schema's declarations make to a model's definitions
    class Builder
      DEFAULTS = {
        name: nil, type: nil, enum: nil, default: nil, primary_key: false,
        null: true, array: false, comment: nil, auto_populated: false,
        read_only: true, required: false, validations: [].freeze
      }.freeze
      OPTIONS = (DEFAULTS.keys - [:name, :type]).freeze
      ASSOCIATION_OPTIONS = [:schema].freeze

      # +association_options+ are each declared association's options, and
      # +values+ each attribute's declared +value+
      attr_reader :conditions, :association_options, :association_conditions, :values

      def initialize
        @changes = {}
        @conditions = {}
        @values = {}
        @association_options = {}
        @association_conditions = {}
      end

      # Declare the attribute +name+, changing it with +options+, or add it
      # when +type+ is given and the model doesn't have it. +if+ and +unless+
      # hide it per record, and +value+ renders it in place of the record's.
      def attribute(name, type = nil, **options)
        name = name.to_s
        conditions = options.extract!(:if, :unless)
        value = options.delete(:value)
        unknown = options.keys - OPTIONS
        raise ArgumentError, "unknown options for attribute #{name}: #{unknown.join(', ')}" if !unknown.empty?

        changes = (@changes[name] ||= {})
        changes[:type] = type.to_s if type
        changes.merge!(options)
        (@conditions[name] ||= []).concat(conditions.to_a) if !conditions.empty?
        @values[name] = value if value
        self
      end

      def attributes(*names)
        names.each { |name| attribute(name) }
        self
      end

      # Declare the association +name+, so an include of it is rendered. +if+
      # and +unless+ hide it per record. +schema+ narrows the included
      # records: they render only what both it and their own Schema declare.
      def association(name, **options)
        name = name.to_s
        conditions = options.extract!(:if, :unless)
        unknown = options.keys - ASSOCIATION_OPTIONS
        raise ArgumentError, "unknown options for association #{name}: #{unknown.join(', ')}" if !unknown.empty?

        (@association_options[name] ||= {}).merge!(options)
        (@association_conditions[name] ||= []).concat(conditions.to_a) if !conditions.empty?
        self
      end

      def associations(*names)
        names.each { |name| association(name) }
        self
      end

      # Take back a declaration, ie. one inherited from a parent Schema
      def remove(*names)
        names.map(&:to_s).each do |name|
          @changes.delete(name)
          @conditions.delete(name)
          @values.delete(name)
          @association_options.delete(name)
          @association_conditions.delete(name)
        end
        self
      end

      # New definitions; those in +default_schema+ are shared, so aren't changed
      def apply(default_schema, model)
        pending = @changes.dup
        definitions = default_schema.filter_map do |definition|
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

      # The model's associations these declarations leave out
      def hidden_associations(model)
        model.reflect_on_all_associations.map { |association| association.name.to_s } - @association_options.keys
      end
    end

    class_attribute :schema_steps, instance_accessor: false, default: [].freeze

    class << self
      # See Builder#attribute. Conditions may be a Symbol naming a method or a
      # Proc. Both run on the Schema instance, take no arguments and read the
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

      def attributes(*names)
        add_step { attributes(*names) }
      end

      # See Builder#association. +schema+ is a Schema class, or a Symbol or
      # Proc run like a condition, on the record including them, that returns
      # one or nil to render the included records with their own Schema alone.
      def association(name, **options)
        schema = options[:schema]
        if schema && !schema.is_a?(Proc) && !schema.is_a?(Symbol) && !(schema.is_a?(Class) && schema < StandardAPI::Schema)
          raise ArgumentError, "the schema of association #{name} must be a subclass of StandardAPI::Schema, a Symbol or a Proc"
        end

        varies = options.key?(:if) || options.key?(:unless) || schema.is_a?(Proc) || schema.is_a?(Symbol)
        # A narrowing Schema can vary too, and may not be fully declared yet
        varies ||= -> { schema.varies_by_requester? } if schema.is_a?(Class)
        add_step(varies: varies) { association(name, **options) }
      end

      def associations(*names)
        add_step { associations(*names) }
      end

      def remove(*names)
        add_step { remove(*names) }
      end

      # Declare attributes only known at runtime. +key+ is a Symbol or Proc that
      # reads +record+ (nil for a model), and records with the same result share
      # them: the block runs on the Schema instance once a request per key, is
      # given the key, and declares with +attribute+, +attributes+,
      # +association+, +associations+ and +remove+.
      # +record+ raises in the block, as the result is shared between records.
      def attributes_for(key, &block)
        raise ArgumentError, 'attributes_for needs a block' if !block

        add_step(key: key, varies: true, &block)
      end

      # Whether the definitions could differ by requester, which fragment
      # caching has to know as its keys can't tell requesters apart. Assumed of
      # conditions, values, attributes_for and an association's +schema+ given
      # as a Symbol or Proc, or one that varies; override to say otherwise.
      def varies_by_requester?
        schema_steps.any? { |step| step[:varies].is_a?(Proc) ? step[:varies].call : step[:varies] }
      end

      private

      # An override would bypass the excludes and the fragment caching check
      def method_added(name)
        if name == :schemas && self != StandardAPI::Schema
          raise StandardAPI::InvalidConfiguration, "#{self.name || 'A Schema'} can't override schemas; declare attributes with attribute, remove and attributes_for instead"
        end

        super
      end

      def add_step(key: nil, varies: false, &block)
        self.schema_steps += [{ key: key, varies: varies, block: block }.freeze]
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
    # +default_schema+, the ones Helpers#schemas_for builds. It can't be
    # overridden, so what it renders always matches hidden_attributes.
    def schemas(default_schema, record)
      builder = builder_for(record)
      definitions = (@applied[builder] ||= {}.compare_by_identity)[default_schema] ||=
        builder.apply(default_schema, model)

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

    # The excludes of +record+'s associations, or a model's with nil: true for
    # one it doesn't render for this requester, and for one rendered through a
    # +schema+, that Schema under Excludes::SCHEMAS, for the included records
    # to apply
    def association_excludes(record)
      builder = builder_for(record)
      excluded = builder.hidden_associations(model).index_with(true)
      failed = failed_association_conditions(record)

      builder.association_options.each do |name, options|
        next excluded[name] = true if failed.include?(name)

        schema = options[:schema]
        schema = resolve(schema, record) if schema.is_a?(Proc) || schema.is_a?(Symbol)
        excluded[name] = { StandardAPI::Excludes::SCHEMAS => [schema] } if schema
      end
      excluded
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

    def attributes(*names)
      declarations.attributes(*names)
    end

    def association(name, **options)
      declarations.association(name, **options)
    end

    def associations(*names)
      declarations.associations(*names)
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
      steps = self.class.schema_steps
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
