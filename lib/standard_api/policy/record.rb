module StandardAPI
  class Policy
    # What one record renders, or a model with a nil record, as one Policy
    # declares it: its model's, or the +policy+ of the association that
    # included it, which takes its place. Built by Policies#record_policy, which
    # views and custom partials call:
    #
    #   policy = record_policy(photo, local_assigns[:policy])
    #
    #   json.set! :format, photo.format if policy.attribute?(:format)
    #
    #   policy.includes(includes).each do |name, sub_include, sub_policy|
    #     json.set! name do
    #       json.partial! 'application/record', record: photo.send(name),
    #         includes: sub_include, policy: sub_policy
    #     end
    #   end
    class Record

      # +policy+ is the instance of the Policy it renders with, nil for a model
      # with none
      attr_reader :model, :record, :policy

      def initialize(controller, model, record, policy)
        @controller = controller
        @model = model
        @record = record
        @policy = policy
      end

      # The definitions of the attributes it renders: the defaults
      # (Policies#default_definitions) as its Policy declares them. Raises
      # MissingPolicy when there is no Policy, so nothing is rendered that no
      # one chose to expose.
      def attributes
        @attributes ||= begin
          raise StandardAPI::MissingPolicy.new(model) if !policy

          names = record ? record.attribute_names : model.attribute_names
          policy.definitions(@controller.send(:default_definitions, model, names), record)
        end
      end

      def attribute?(name)
        (@attribute_names ||= attributes.map { |definition| definition[:name] }.to_set).include?(name.to_s)
      end

      # The includes of +includes+ it renders, as [name, sub_include,
      # sub_policy]: +sub_include+ is what to include of them, and +sub_policy+
      # the Policy class to render them with (#association_policy), or nil.
      def includes(includes)
        includes.filter_map do |name, sub_include|
          next if StandardAPI::Controller::RESERVED_INCLUDE_KEYS.include?(name.to_s)
          next if !include?(name)

          [name, sub_include, association_policy(name)]
        end
      end

      # Whether an include of +name+, an association or a method, renders:
      # the Policy declares it and shows it for the record. Without a Policy,
      # nothing does.
      def include?(name)
        !!policy&.association?(record, name)
      end

      # The names of the attributes and associations of the model a request
      # may order by (Policy#permitted_orders), decided for the model whatever
      # the record. Without a Policy, nothing can be.
      def orderable
        policy ? policy.permitted_orders : []
      end

      # What a create or update of the record may set, the model being a
      # create, as strong parameters permit them
      # (Policy#permitted_attributes). Without a Policy, nothing.
      def writable
        policy ? policy.permitted_attributes(record) : []
      end

      # What a create or update of the record sets, the model being a create,
      # as name => value (Policy#assigned_attributes). Without a Policy,
      # nothing.
      def assigned_attributes
        policy ? policy.assigned_attributes(record) : {}
      end

      # Run its Policy's filters on +params+, the permitted params of a create
      # or update of the record, the model being a create
      # (Policy#filter_params). Returns +params+; without a Policy, as they
      # are.
      def filter_params(params)
        policy ? policy.filter_params(record, params) : params
      end

      # The names #assigned_attributes sets, without working out their values
      def assigned_attribute_names
        policy ? policy.assigned_attribute_names(record) : []
      end

      # The names of the associations a create or update of the record may
      # write through nested attributes, the model being a create, or on +on+
      # (:create or :update) when it's given
      # (Policy#permitted_associations). Without a Policy, none.
      def writable_associations(on: nil)
        policy ? policy.permitted_associations(record, on: on) : []
      end

      # The Policy class the records written through the association +name+
      # are written with in place of their own model's
      # (Policy#writable_policy), or nil
      def writable_policy(name)
        policy&.writable_policy(record, name)
      end

      # What every request is ordered by after its own orders
      # (Policy#permitted_required_orders), decided for the model whatever the
      # record. Without a Policy, nothing.
      def required_orders
        policy ? policy.permitted_required_orders : []
      end

      # What a request may filter on (Policy#permitted_wheres), as name =>
      # :all or the canonical operators it permits, decided for the model
      # whatever the record. Without a Policy, nothing can be.
      def filterable
        policy ? policy.permitted_wheres : {}
      end

      # The Policy class the records included through +name+ render with in
      # place of their own model's, or nil
      def association_policy(name)
        policy&.association_policy(record, name)
      end

      # The value of attribute +name+ to render (Policy#value)
      def value(name)
        policy ? policy.value(record, name) : record.send(name)
      end

      # Whether it hides +name+, an attribute or association of the model.
      # Unlike #attributes, a model with no Policy doesn't raise: it hides
      # nothing.
      def hidden?(name)
        name = name.to_s
        if model.attribute_names.include?(name)
          !!policy&.hidden_attributes(record)&.include?(name)
        elsif model.reflect_on_association(name)
          !include?(name)
        else
          false
        end
      end

      # The record's validation errors, less those on what it hides, whose
      # messages usually quote the value. A key like `photos.caption` is
      # matched on its leading segment.
      def errors
        errors = record.errors.to_hash
        errors.default_proc = nil
        errors.reject { |key, _| hidden?(key.to_s.split('.').first) }
      end

    end
  end
end
