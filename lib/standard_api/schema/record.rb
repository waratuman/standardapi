module StandardAPI
  class Schema
    # What one record renders, or a model with a nil record, as one Schema
    # declares it: its model's, or the +schema+ of the association that
    # included it, which takes its place. Built by Schemas#schema_for, which
    # views and custom partials call:
    #
    #   schema = schema_for(photo, local_assigns[:schema])
    #
    #   json.set! :format, photo.format if schema.attribute?(:format)
    #
    #   if includes[:account] && schema.include?(:account)
    #     json.partial! 'application/record', record: photo.account,
    #       includes: includes[:account], schema: schema.schema_through(:account)
    #   end
    class Record

      # +schema+ is the instance of the Schema it renders with, nil for a model
      # with none, and +through+ the class given by the including association,
      # if any
      attr_reader :model, :record, :schema

      def initialize(controller, model, record, schema, through)
        @controller = controller
        @model = model
        @record = record
        @schema = schema
        @through = through
      end

      # The definitions of the attributes it renders, from
      # Helpers#schemas_for
      def attributes
        @attributes ||= @controller.schemas_for(record || model, @through)
      end

      def attribute?(name)
        (@attribute_names ||= attributes.map { |definition| definition[:name] }.to_set).include?(name.to_s)
      end

      # Whether an include of +name+ renders: an association the Schema
      # declares and shows, or an include that isn't an association
      def include?(name)
        !model.reflect_on_association(name.to_s) || !schema || schema.association?(record, name)
      end

      # The Schema class the records included through +name+ render with in
      # place of their own model's, or nil
      def schema_through(name)
        schema&.association_schema(record, name)
      end

      # The value of attribute +name+ to render (Schema#value)
      def value(name)
        schema ? schema.value(record, name) : record.send(name)
      end

      # Whether it hides +name+, an attribute or association of the model.
      # Unlike #attributes, a model with no Schema doesn't raise: it hides
      # nothing.
      def hidden?(name)
        name = name.to_s
        if model.attribute_names.include?(name)
          !!schema&.hidden_attributes(record)&.include?(name)
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
