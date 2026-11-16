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

    # What +record_or_model+ renders (a Schema::Record; for a model, the record
    # is nil): its model's Schema, or +through+, the Schema class the
    # association that included it gives, in its place. To keep what the
    # model's Schema hides, +through+ inherits from it.
    def record_schema(record_or_model, through = nil)
      model, record = record_or_model.is_a?(Class) ? [record_or_model, nil] : [record_or_model.class, record_or_model]
      schema = through ? schema_instance(through, model) : model_schema(model)
      (@rendering_schemas ||= {}.compare_by_identity)[record] = schema if record
      StandardAPI::Schema::Record.new(self, model, record, schema)
    end

    private

    # The attributes of +model+ as StandardAPI exposes them. The JSON Schemas
    # (Helpers::JSONSchema) are built from this, so code that needs the
    # same information (an MCP tool describing a model, say) can read it
    # directly instead of fetching a schema and parsing it back.
    #
    # These are the defaults: Schema::Record#attributes passes them through
    # the Schema, and record_schema(record_or_model).attributes gives the
    # result. application/_record renders a record from it, so the
    # definitions are also what a record is rendered with: an attribute its
    # Schema leaves out isn't rendered, and one it adds is read from the record
    # by name.
    #
    # Returns an Array of Hashes, one per entry in +names+: for a model,
    # `model.attribute_names`, the columns, then any attributes declared
    # without one; for a record, `record.attribute_names`, which is what its
    # query selected: a record
    # loaded with `select(:id)` has only `id`, and one loaded with
    # `select('*, 1 AS rank')` also has `rank`. The model types every
    # attribute, so one it doesn't have, like `rank`, has a nil `type`.
    #
    #   name            String   the attribute name
    #   type            String   the ActiveModel type,
    #                            `type_for_attribute(name).type`, so it is the
    #                            same on every adapter and keeps "date", "time"
    #                            and "datetime" apart. "string" for an enum. nil
    #                            for a type that doesn't name itself
    #   enum            Array    the names an enum accepts, or nil if the
    #                            attribute isn't an enum
    #   default         Object   the column default, cast to Ruby. For an enum,
    #                            the name of the default value
    #   primary_key     Boolean
    #   null            Boolean  whether the column allows NULL
    #   array           Boolean  whether the column is an array; "type" is then
    #                            the type of its elements
    #   comment         String   the column comment, or nil
    #   auto_populated  Boolean  whether the database fills the column in
    #                            itself, ie. a serial id or a column with a
    #                            function default
    #   read_only       Boolean  true when the attribute can't be changed
    #                            through the API: it is missing from the ACL's
    #                            `attributes`, or the model marks it readonly
    #                            (`attr_readonly`)
    #   required        Boolean  true when a create must set it: the column is
    #                            NOT NULL and writable on create (permitted by
    #                            the ACL, not auto populated; an
    #                            `attr_readonly` attribute can be set on
    #                            create), or it has a presence
    #                            validation, or an acceptance validation
    #                            without `allow_nil`
    #   validations     Array    the model's validations of the attribute, as
    #                            `{ kind: :length, options: { maximum: 12 } }`
    #
    # An attribute with no column has nil `default`, `null`, `comment` and
    # `auto_populated`.
    #
    # The ACL is consulted without a record, as `attributes(nil)`, so
    # `read_only` is the model wide answer.
    #
    # They're built once a request per model and set of attribute names, so
    # records loaded by the same query share them, and so does what the Schema
    # makes of them.
    def default_definitions(model, names)
      @default_definitions ||= {}
      @default_definitions[[model, names]] ||= begin
        permitted_attributes = model_attributes(model)&.map(&:to_s)

        columns = model.columns_hash
        names.map do |name|
          attribute_definition(model, name, columns[name], permitted_attributes.nil? || permitted_attributes.include?(name))
        end
      end
    end

    def attribute_definition(model, name, column, permitted)
      attribute_type = model.type_for_attribute(name)
      enum = model.defined_enums[name] if attribute_type.is_a?(::ActiveRecord::Enum::EnumType)
      default = column_default_value(column, model) if column
      auto_populated = (!!column.auto_populated? if column)
      validations = model.validators_on(name).map { |v| { kind: v.kind, options: v.options } }

      read_only = !permitted || model.readonly_attribute?(name)
      writable_on_create = permitted && !auto_populated

      {
        name: name,
        type: enum ? 'string' : attribute_type.type&.to_s,
        enum: enum&.keys,
        default: enum ? enum.key(default) : default,
        primary_key: name == model.primary_key,
        null: column&.null,
        array: column ? column.array : false,
        comment: column&.comment,
        auto_populated: auto_populated,
        read_only: read_only,
        required: (column&.null == false && writable_on_create) || validations.any? { |v|
          v[:kind] == :presence || (v[:kind] == :acceptance && v[:options][:allow_nil] != true)
        },
        validations: validations
      }
    end

    def column_default_value(column, model)
      return nil if column.default.nil?

      cast_type_for_column(column, model).deserialize(column.default)
    end

    # Resolves a column's database cast type across Rails versions. The public
    # API for this has changed repeatedly:
    #   * Rails 7.2 / 8.0 -> connection.lookup_cast_type_from_column(column)
    #   * Rails 8.1       -> column.fetch_cast_type(connection)
    #   * Rails main      -> column.cast_type (public reader again)
    def cast_type_for_column(column, model)
      if column.respond_to?(:fetch_cast_type)
        column.fetch_cast_type(model.connection)
      elsif column.respond_to?(:cast_type)
        column.cast_type
      else
        model.connection.lookup_cast_type_from_column(column)
      end
    end

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
