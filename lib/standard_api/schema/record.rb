module StandardAPI
  class Schema
    # What one record renders, or a model with a nil record: what its model's
    # Schema declares, less what each Schema narrowing it hides. A record is
    # narrowed by the +schema+ of the association that included it. Built by
    # Schemas#schema_for, which views and custom partials call:
    #
    #   schema = schema_for(photo, local_assigns[:schemas])
    #
    #   json.set! :format, photo.format if schema.attribute?(:format)
    #
    #   if includes[:account] && schema.include?(:account)
    #     json.partial! 'application/record', record: photo.account,
    #       includes: includes[:account], schemas: schema.narrowing_for(:account)
    #   end
    class Record

      attr_reader :model, :record, :narrowing

      # +schema+ is the model's Schema instance, and +narrowing+ the instances
      # of the Schemas narrowing it
      def initialize(controller, model, record, schema, narrowing)
        @controller = controller
        @model = model
        @record = record
        @narrowing = narrowing
        @schemas = [schema, *narrowing].compact
      end

      # The definitions of the attributes it renders, from
      # Helpers#schemas_for
      def attributes
        @attributes ||= begin
          definitions = @controller.schemas_for(record || model)
          hidden = narrowing.flat_map { |schema| schema.hidden_attributes(record) }
          hidden.empty? ? definitions : definitions.reject { |definition| hidden.include?(definition[:name]) }
        end
      end

      def attribute?(name)
        (@attribute_names ||= attributes.map { |definition| definition[:name] }.to_set).include?(name.to_s)
      end

      # Whether an include of +name+ renders: an association every Schema
      # declares and shows, or an include that isn't an association
      def include?(name)
        !model.reflect_on_association(name.to_s) || @schemas.all? { |schema| schema.association?(record, name) }
      end

      # The Schema classes narrowing the records included through +name+
      def narrowing_for(name)
        @schemas.filter_map { |schema| schema.association_schema(record, name) }.uniq
      end

      # Whether it hides +name+, an attribute or association of the model.
      # Unlike #attributes, a model with no Schema doesn't raise: it hides
      # nothing.
      def hidden?(name)
        name = name.to_s
        if model.attribute_names.include?(name)
          @schemas.any? { |schema| schema.hidden_attributes(record).include?(name) }
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
