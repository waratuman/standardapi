module StandardAPI
  module ActiveRecord
    module ConnectionAdapters
      module Column
        # Returns whether the column is an array, or false if the adapter doesn't support one
        def array
          false
        end
      end
    end
  end
end
