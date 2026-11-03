module StandardAPI
  # The sibling of AccessControlList for declaring how a model's attributes
  # are described. A controller nests a +Schema+ module whose
  # +schemas(default_schema, record)+ adjusts the definitions
  # Helpers#schemas_for builds for its model, given the record being rendered
  # (nil for a model):
  #
  #   class PhotosController < ApplicationController
  #     module Schema
  #       def schemas(default_schema, record)
  #         default_schema.map { |s| s[:name] == 'caption' ? s.merge(comment: '...') : s }
  #       end
  #     end
  #   end
  #
  # Include this in the base controller, as AccessControlList; the Schema is
  # included into it as +photo_schemas+.
  module Schemas

    # Include the +Schema+ module nested in each controller into its base
    # controller (the topmost class that includes Schemas)
    def self.load!
      Helpers.each_nested(self, :Schema) do |base, mod, prefix|
        include_schema(base, mod, prefix)
      end
    end

    # Rename the +schemas+ method of +mod+ to +<prefix>_schemas+ and include
    # it into +application_controller+
    def self.include_schema(application_controller, mod, prefix)
      Helpers.include_renamed(application_controller, mod, schemas: "#{prefix}_schemas")
    end

    # Pass +schemas+, the attribute definitions built for +model+ by
    # Helpers#schemas_for, and +record+ (nil for a model) through the
    # +schemas+ method of its controller's Schema module (+<model>_schemas+)
    # and return its result. Returns +schemas+ unchanged when there is none.
    def model_schemas(model, schemas, record = nil)
      return schemas if !(method_name = model_method_for(model, :schemas))

      self.send(method_name, schemas, record)
    end

  end
end
