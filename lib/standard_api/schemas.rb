module StandardAPI
  # The sibling of AccessControlList that finds each controller's nested
  # StandardAPI::Schema and gives a base controller the means to use it. Include
  # this in the base controller, as AccessControlList.
  module Schemas

    def self.included(base)
      base.class_attribute :standard_api_schemas, instance_accessor: false, default: {}.freeze
    end

    # Register the +Schema+ nested in each controller with its base controller
    # (the topmost class that includes Schemas)
    def self.load!
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
    # return the result. Returns +schemas+ unchanged when there is none.
    def model_schemas(model, schemas, record = nil)
      schema = model_schema(model)
      schema ? schema.schemas(schemas, record) : schemas
    end

    private

    # The Schema instance for +model+ this request, falling back to the one for
    # its base class (ie. an STI subclass), or nil if there is none
    def model_schema(model)
      @model_schema_instances ||= {}
      return @model_schema_instances[model] if @model_schema_instances.key?(model)

      classes = model.respond_to?(:base_class) ? [model, model.base_class].uniq : [model]
      klass = classes.filter_map { |k| self.class.standard_api_schemas[model_name(k)] }.first
      @model_schema_instances[model] = klass&.new(self, model)
    end

    # The attributes +record+'s Schema hides from this requester
    def model_hidden_attributes(record)
      model_schema(record.class)&.hidden_attributes(record)
    end

  end
end
