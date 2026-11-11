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
    # Helpers#schemas_for, and +record+ (nil for a model) through its Schema and
    # return the result. Raises MissingSchema when there is none, so nothing is
    # rendered that no one chose to expose.
    def model_schemas(model, schemas, record = nil)
      schema = model_schema(model)
      raise StandardAPI::MissingSchema.new(model) if !schema

      schema.schemas(schemas, record)
    end

    # What +model+'s Schema doesn't render of +record+, or of the model with
    # nil, as an exclude tree: its hidden attributes and the excludes of its
    # associations. +through+ are the Schemas an including record narrows it
    # with, whose excludes are added, so they can only hide more.
    def schema_excludes(model, record = nil, through: nil)
      schemas = [model_schema(model)] + Array(through).map { |schema| narrowing_schema(schema, model) }
      schemas.compact.reduce(StandardAPI::Excludes.normalize(nil)) do |excluded, schema|
        hidden = schema.hidden_attributes(record).index_with(true)
        StandardAPI::Excludes.deep_merge(excluded, StandardAPI::Excludes.deep_merge(hidden, schema.association_excludes(record)))
      end
    end

    private

    # The instance of +schema+, given by an association's +schema+, for
    # +model+ this request
    def narrowing_schema(schema, model)
      (@narrowing_schemas ||= {})[[schema, model]] ||= schema.new(self, model)
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
