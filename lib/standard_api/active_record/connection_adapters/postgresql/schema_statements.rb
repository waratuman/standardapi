module StandardAPI
  module ActiveRecord
    module ConnectionAdapters
      class PostgreSQL
        module SchemaStatements
          # Returns a comment stored in database for given table
          def database_comment(database_name=nil) # :nodoc:
            database_name ||= current_database
    
            scope = quoted_scope(database_name, type: "BASE TABLE")
            if scope[:name]
              query_value(<<~SQL, "SCHEMA")
                SELECT pg_catalog.shobj_description(d.oid, 'pg_database')
                FROM   pg_catalog.pg_database d
                WHERE  datname = #{scope[:name]};
              SQL
            end
          end
  
        end
      end
    end
  end
end

# Apply the patch only when the PostgreSQL adapter is actually loaded. Requiring
# the adapter eagerly pulls in the `pg` gem, forcing it on applications that use
# another database (e.g. SQLite). The :active_record_postgresqladapter load hook
# fires from the adapter itself, so this runs only when pg is really in use.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  include StandardAPI::ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaStatements
end