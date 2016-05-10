require 'msgpack'

# QueryEncoding middleware intercepts and parsing the query sting as MessagePack
# if the `Query-Encoding` header is set to `application/msgpack`
#
# Usage:
#
#   require 'standard_api/middleware/query_encoding'
#
# And in the Rails config
#
#   config.middleware.insert_after Rack::MethodOverride, StandardAPI::Middleware::QueryEncoding
module StandardAPI
  module Middleware
    class QueryEncoding
      MSGPACK_MIME_TYPE = "application/msgpack".freeze
      HTTP_METHOD_OVERRIDE_HEADER = "HTTP_QUERY_ENCODING".freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        if !env[Rack::QUERY_STRING].empty? && env[HTTP_METHOD_OVERRIDE_HEADER] == MSGPACK_MIME_TYPE
          env[Rack::RACK_REQUEST_QUERY_STRING] = env[Rack::QUERY_STRING]
          env[Rack::RACK_REQUEST_QUERY_HASH] = MessagePack.unpack(CGI.unescape(env[QUERY_STRING]))
        end

        @app.call(env)
      end

    end
  end
end