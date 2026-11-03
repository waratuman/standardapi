module StandardAPI
  module Helpers
    # Helpers for building `json_schema.json`, included in StandardAPI::Helpers
    module JSONSchemaHelper

      # The JSON Schema for a Helpers#schemas_for `type`, or an empty schema
      # for a type it doesn't know
      def json_schema_for_type(type)
        case type
        when 'string', 'text', 'citext', 'inet', 'cidr', 'macaddr', 'ltree'
          {type: 'string'}
        when 'uuid'
          {type: 'string', format: 'uuid'}
        when 'integer'
          {type: 'integer'}
        when 'float'
          {type: 'number'}
        when 'decimal', 'money'
          # A BigDecimal renders as a String in JSON, and either is accepted
          {type: ['number', 'string']}
        when 'boolean'
          {type: 'boolean'}
        when 'date'
          {type: 'string', format: 'date'}
        when 'datetime', 'timestamp', 'timestamptz', 'time'
          # A time column renders as a full timestamp, not "HH:MM:SS"
          {type: 'string', format: 'date-time'}
        when 'interval'
          {type: 'string', format: 'duration'}
        when 'json', 'jsonb', 'hstore'
          {type: 'object'}
        when 'binary'
          {type: 'string', contentMediaType: 'application/octet-stream'}
        else
          {}
        end
      end

    end
  end
end
