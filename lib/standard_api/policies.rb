module StandardAPI
  # Finds each controller's nested StandardAPI::Policy and gives a base
  # controller the means to use it. StandardAPI::Controller includes it.
  module Policies

    def self.included(base)
      # Including it again would reset what load! registered
      return if base.respond_to?(:standard_api_policies)

      base.class_attribute :standard_api_policies, instance_accessor: false, default: {}.freeze
    end

    # Register the +Policy+ nested in each controller with its base controller
    # (the topmost class that includes Policies)
    def self.load!
      Helpers.each_nested(self, :Policy) do |base, policy, prefix|
        register(base, policy, prefix)
      end
    end

    def self.register(base, policy, prefix)
      if !(policy.is_a?(Class) && policy < StandardAPI::Policy)
        raise StandardAPI::InvalidConfiguration, "#{policy.name} must be a subclass of StandardAPI::Policy"
      end

      existing = base.standard_api_policies[prefix]
      return if existing.equal?(policy)

      if existing
        raise StandardAPI::InvalidConfiguration, "#{policy.name} and #{existing.name} both describe #{prefix}; the Policy of one model is shared by all of its controllers, so define it once"
      end

      base.standard_api_policies = base.standard_api_policies.merge(prefix => policy).freeze
    end

    # What +record_or_model+ renders (a Policy::Record; for a model, the record
    # is nil): its model's Policy, or +through+, the Policy class the
    # association that included it gives, in its place. To keep what the
    # model's Policy hides, +through+ inherits from it.
    def record_policy(record_or_model, through = nil)
      model, record = record_or_model.is_a?(Class) ? [record_or_model, nil] : [record_or_model.class, record_or_model]
      policy = through ? policy_instance(through, model) : model_policy(model)
      (@rendering_policies ||= {}.compare_by_identity)[record] = policy if record
      StandardAPI::Policy::Record.new(self, model, record, policy)
    end

    private

    # The attributes of +model+ as StandardAPI exposes them. The JSON Schemas
    # (Helpers::JSONSchema) are built from this, so code that needs the
    # same information (an MCP tool describing a model, say) can read it
    # directly instead of fetching a schema and parsing it back.
    #
    # These are the defaults: Policy::Record#attributes passes them through
    # the Policy, and record_policy(record_or_model).attributes gives the
    # result. application/_record renders a record from it, so the
    # definitions are also what a record is rendered with: an attribute its
    # Policy leaves out isn't rendered, and one it adds is read from the record
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
    #   read_only       Boolean  true, until the Policy makes the attribute
    #                            `writable`
    #   required        Boolean  true when it has a presence validation, or
    #                            an acceptance validation without
    #                            `allow_nil`; the Policy also makes a NOT NULL
    #                            column it makes `writable` required
    #   validations     Array    the model's validations of the attribute, as
    #                            `{ kind: :length, options: { maximum: 12 } }`
    #
    # An attribute with no column has nil `default`, `null`, `comment` and
    # `auto_populated`.
    #
    # They're built once a request per model and set of attribute names, so
    # records loaded by the same query share them, and so does what the Policy
    # makes of them.
    def default_definitions(model, names)
      @default_definitions ||= {}
      @default_definitions[[model, names]] ||= begin
        columns = model.columns_hash
        names.map { |name| attribute_definition(model, name, columns[name]) }
      end
    end

    def attribute_definition(model, name, column)
      attribute_type = model.type_for_attribute(name)
      enum = model.defined_enums[name] if attribute_type.is_a?(::ActiveRecord::Enum::EnumType)
      default = column_default_value(column, model) if column
      auto_populated = (!!column.auto_populated? if column)
      validations = model.validators_on(name).map { |v| { kind: v.kind, options: v.options } }


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
        read_only: true,
        required: validations.any? { |v|
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

    # The Policy instance +record+ was last given by record_policy, which is what
    # it renders with, or else its model's
    def rendering_policy(record)
      @rendering_policies&.key?(record) ? @rendering_policies[record] : model_policy(record.class)
    end

    # The instance of +policy+, given by an association's +policy+, for
    # +model+ this request
    def policy_instance(policy, model)
      (@policy_instances ||= {})[[policy, model]] ||= policy.new(self, model)
    end

    # The Policy instance for +model+ this request, falling back to the one for
    # its base class (ie. an STI subclass), or nil if there is none
    def model_policy(model)
      @model_policy_instances ||= {}
      return @model_policy_instances[model] if @model_policy_instances.key?(model)

      classes = model.respond_to?(:base_class) ? [model, model.base_class].uniq : [model]
      klass = classes.filter_map { |k| self.class.standard_api_policies[model_name(k)] || named_policy(k) }.first
      @model_policy_instances[model] = klass&.new(self, model)
    end

    # A model with no controller of its own, such as one only rendered as an
    # include, declares its Policy by name: ToolCallPolicy for ToolCall
    def named_policy(model)
      policy = "#{model.name}Policy".safe_constantize
      policy if policy.is_a?(Class) && policy < StandardAPI::Policy
    end

  end
end
