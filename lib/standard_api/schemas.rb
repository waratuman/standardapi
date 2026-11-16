module StandardAPI
  # Finds each controller's nested StandardAPI::Schema and gives a base
  # controller the means to use it. StandardAPI::Controller includes it.
  module Schemas

    def self.included(base)
      # Including it again would reset what load! registered
      return if base.respond_to?(:standard_api_schemas)

      base.class_attribute :standard_api_schemas, instance_accessor: false, default: {}.freeze
    end

    # Register the +Schema+ nested in each controller with its base controller
    # (the topmost class that includes Schemas)
    def self.load!
      if defined?(::ApplicationHelper) && ::ApplicationHelper.method_defined?(:excludes)
        raise StandardAPI::InvalidConfiguration, "ApplicationHelper#excludes is no longer supported, so it would hide nothing. Remove it, and leave what it hid out of each model's Schema"
      end

      Helpers.each_nested(self, :Schema) do |base, schema, prefix|
        register(base, schema, prefix)
      end
    end

    def self.register(base, schema, prefix)
      if !(schema.is_a?(Class) && schema < StandardAPI::Schema)
        raise StandardAPI::InvalidConfiguration, "#{schema.name} must be a subclass of StandardAPI::Schema"
      end

      existing = base.standard_api_schemas[prefix]
      return if existing.equal?(schema)

      if existing
        raise StandardAPI::InvalidConfiguration, "#{schema.name} and #{existing.name} both describe #{prefix}; the Schema of one model is shared by all of its controllers, so define it once"
      end

      base.standard_api_schemas = base.standard_api_schemas.merge(prefix => schema).freeze
    end

    # Pass +schemas+, the attribute definitions built for +model+ by
    # Helpers#attribute_definitions, and +record+ (nil for a model) through its Schema, or
    # +through+, a Schema class used in its place, and return the result.
    # Raises MissingSchema when there is none, so nothing is rendered that no
    # one chose to expose.
    def model_schemas(model, schemas, record = nil, through = nil)
      schema = through ? schema_instance(through, model) : model_schema(model)
      raise StandardAPI::MissingSchema.new(model) if !schema

      schema.schemas(schemas, record)
    end

    # What +record_or_model+ renders (a Schema::Record; for a model, the record
    # is nil): its model's Schema, or +through+, the Schema class the
    # association that included it gives, in its place. To keep what the
    # model's Schema hides, +through+ inherits from it.
    def record_schema(record_or_model, through = nil)
      model, record = record_or_model.is_a?(Class) ? [record_or_model, nil] : [record_or_model.class, record_or_model]
      schema = through ? schema_instance(through, model) : model_schema(model)
      (@rendering_schemas ||= {}.compare_by_identity)[record] = schema if record
      StandardAPI::Schema::Record.new(self, model, record, schema, through)
    end

    private

    # The Schema instance +record+ was last given by record_schema, which is what
    # it renders with, or else its model's
    def rendering_schema(record)
      @rendering_schemas&.key?(record) ? @rendering_schemas[record] : model_schema(record.class)
    end

    # The instance of +schema+, given by an association's +schema+, for
    # +model+ this request
    def schema_instance(schema, model)
      (@schema_instances ||= {})[[schema, model]] ||= schema.new(self, model)
    end

    # The Schema instance for +model+ this request, falling back to the one for
    # its base class (ie. an STI subclass), or nil if there is none
    def model_schema(model)
      @model_schema_instances ||= {}
      return @model_schema_instances[model] if @model_schema_instances.key?(model)

      classes = model.respond_to?(:base_class) ? [model, model.base_class].uniq : [model]
      klass = classes.filter_map { |k| self.class.standard_api_schemas[model_name(k)] || named_schema(k) }.first
      @model_schema_instances[model] = klass&.new(self, model)
    end

    # A model with no controller of its own, such as one only rendered as an
    # include, declares its Schema by name: ToolCallSchema for ToolCall
    def named_schema(model)
      schema = "#{model.name}Schema".safe_constantize
      schema if schema.is_a?(Class) && schema < StandardAPI::Schema
    end

  end
end
