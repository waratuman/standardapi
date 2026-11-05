require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/hash/keys'

module StandardAPI
  # Declares how a model's attributes are described and rendered. Nest a
  # subclass in the model's controller; StandardAPI::Schemas finds it. Like
  # strong parameters, only what it declares is used, so a new column stays
  # hidden until it's listed. Types and validations still come from the model.
  #
  #   class PhotosController < ApplicationController
  #     class Schema < StandardAPI::Schema
  #       controller_methods :admin?
  #
  #       attributes :id, :format, :created_at
  #       attribute :caption, comment: 'Shown under the photo'
  #       attribute :thumbnail_url, :string
  #       attribute :location, if: :admin?
  #
  #       attributes_for :account_id do |account_id|
  #         Field.where(account_id: account_id).each do |field|
  #           attribute field.key, field.value_type, comment: field.name
  #         end
  #       end
  #
  #       private
  #
  #       def account_id(record) = record&.account_id
  #     end
  #   end
  #
  # One instance serves a model for the length of a request, on its controller.
  class Schema

    # The changes a Schema's declarations make to a model's definitions
    class Builder
      DEFAULTS = {
        name: nil, type: nil, enum: nil, default: nil, primary_key: false,
        null: true, array: false, comment: nil, auto_populated: false,
        read_only: true, required: false, validations: [].freeze
      }.freeze
      OPTIONS = (DEFAULTS.keys - [:name, :type]).freeze

      attr_reader :conditions

      def initialize
        @changes = {}
        @conditions = {}
      end

      # Declare the attribute +name+, changing it with +options+, or add it
      # when +type+ is given and the model doesn't have it. +if+ and +unless+
      # hide it per record.
      def attribute(name, type = nil, **options)
        name = name.to_s
        conditions = options.extract!(:if, :unless)
        unknown = options.keys - OPTIONS
        raise ArgumentError, "unknown options for attribute #{name}: #{unknown.join(', ')}" if !unknown.empty?

        changes = (@changes[name] ||= {})
        changes[:type] = type.to_s if type
        changes.merge!(options)
        (@conditions[name] ||= []).concat(conditions.to_a) if !conditions.empty?
        self
      end

      def attributes(*names)
        names.each { |name| attribute(name) }
        self
      end

      # Take back a declaration, ie. one inherited from a parent Schema
      def remove(*names)
        names.map(&:to_s).each do |name|
          @changes.delete(name)
          @conditions.delete(name)
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
    end

    class_attribute :schema_steps, instance_accessor: false, default: [].freeze

    class << self
      # See Builder#attribute. Conditions may be a Symbol naming a method or a
      # Proc. Both run on the Schema instance and are given the record, or nil
      # for a model, when they take an argument.
      def attribute(name, type = nil, **options)
        conditional = options.key?(:if) || options.key?(:unless)
        add_step(varies: conditional) { attribute(name, type, **options) }
      end

      def attributes(*names)
        add_step { attributes(*names) }
      end

      def remove(*names)
        add_step { remove(*names) }
      end

      # Declare attributes only known at runtime. +key+ is a Symbol or Proc given
      # the record (nil for a model), and records with the same result share
      # them: the block runs on the Schema instance once a request per key, is
      # given the key, and declares with +attribute+, +attributes+ and +remove+.
      def attributes_for(key, &block)
        raise ArgumentError, 'attributes_for needs a block' if !block

        add_step(key: key, varies: true, &block)
      end

      # Make methods of the controller, including private ones, available to
      # the Schema. Only what's listed is, so a typo raises rather than falling
      # through to something else.
      def controller_methods(*names)
        names.each do |name|
          define_method(name) { |*args, **options, &block| controller.send(name, *args, **options, &block) }
          private name
        end
      end

      # Whether the definitions could differ by requester, which fragment
      # caching has to know as its keys can't tell requesters apart. Assumed of
      # anything StandardAPI can't see through; override to say otherwise.
      def varies_by_requester?
        schema_steps.any? { |step| step[:varies] } || instance_method(:schemas).owner != StandardAPI::Schema
      end

      private

      def add_step(key: nil, varies: false, &block)
        self.schema_steps += [{ key: key, varies: varies, block: block }.freeze]
      end
    end

    attr_reader :controller, :model

    controller_methods :params

    def initialize(controller, model)
      @controller = controller
      @model = model
      @builders = {}
      @applied = {}.compare_by_identity
      @undeclared = {}.compare_by_identity
      @failed = {}.compare_by_identity
    end

    # The definitions to use for +record+, or nil for a model. Override this,
    # calling +super+, for what the declarations can't express. Hide attributes
    # with +if+ or +remove+ rather than here, as only those reach the excludes
    # that keep hidden attributes out of validation errors.
    def schemas(default_schema, record)
      builder = builder_for(record)
      definitions = (@applied[builder] ||= {}.compare_by_identity)[default_schema] ||=
        builder.apply(default_schema, model)

      failed = failed_conditions(record)
      failed.empty? ? definitions : definitions.reject { |definition| failed.include?(definition[:name]) }
    end

    # Names of the attributes +record+ doesn't render for this requester
    def hidden_attributes(record)
      builder = builder_for(record)
      undeclared = @undeclared[builder] ||= builder.hidden_attributes(model)
      undeclared + failed_conditions(record)
    end

    private

    def attribute(name, type = nil, **options)
      declarations.attribute(name, type, **options)
    end

    def attributes(*names)
      declarations.attributes(*names)
    end

    def remove(*names)
      declarations.remove(*names)
    end

    def declarations
      @declarations || raise(ArgumentError, 'declare attributes in the class body or an attributes_for block')
    end

    def failed_conditions(record)
      @failed[record] ||= builder_for(record).conditions.filter_map do |name, conditions|
        name if conditions.any? { |kind, condition| !!resolve(condition, record) == (kind == :unless) }
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
      callable = method(callable) if callable.is_a?(Symbol)
      args = callable.arity > 0 ? [record] : []
      callable.is_a?(Proc) ? instance_exec(*args, &callable) : callable.call(*args)
    end

  end
end
