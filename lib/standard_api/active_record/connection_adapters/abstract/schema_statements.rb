module StandardAPI
  module ActiveRecord
    module ConnectionAdapters
      module SchemaStatements
        # Returns the database comment, or nil if the adapter doesn't support one
        def database_comment(database_name = nil) # :nodoc:
          nil
        end
      end
    end
  end
end
