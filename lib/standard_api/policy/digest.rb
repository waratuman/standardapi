require 'active_support/digest'
require 'active_support/core_ext/object/json'

module StandardAPI
  class Policy

    # Stands in for a Policy instance to record what a Policy's declarations
    # are, without a controller, model or record: each step that isn't an
    # +attributes_for+ only calls the declaration it was made with.
    class Declarations
      attr_reader :calls

      def initialize
        @calls = []
      end

      [
        :attribute, :attributes, :association, :associations, :filterable,
        :required_orders, :writable, :assign, :filter, :remove
      ].each do |declaration|
        define_method(declaration) do |*args, **options, &block|
          @calls << [declaration, args, options, block]
          self
        end
      end
    end

    class << self
      # Identifies what this Policy declares, what it inherits included, for
      # the fragment cache keys in the views: a fragment rendered with other
      # declarations, ie. before a deploy that hides an attribute, has another
      # key, so isn't served once they change.
      #
      # It's the same in every process and on every boot, as the cache is
      # shared between them. Another Policy a declaration gives, ie. an
      # association's +policy+, is identified by name only; the key of a
      # fragment that renders with it includes its digest too
      # (Policies#policy_cache_key). A Proc is identified by where it's
      # defined, its file and line, as its body can't be read: changing the
      # body of one without moving it doesn't change the digest. One that
      # decides what renders (+if+, +unless+, +value+, +policy+ or
      # +attributes_for+) makes the Policy vary by requester, so what it
      # renders isn't cached to begin with, unless +varies_by_requester?+ is
      # overridden.
      #
      # Computed once for a class, and again only if it declares more.
      def cache_digest
        steps = policy_steps
        return @cache_digest[1] if @cache_digest && @cache_digest[0].equal?(steps)

        digest = ActiveSupport::Digest.hexdigest(declaration_signature(steps))
        @cache_digest = [steps, digest].freeze
        digest
      end

      private

      def declaration_signature(steps)
        declarations = Declarations.new
        steps.each do |step|
          if step[:key]
            declarations.calls << [:attributes_for, [step[:key]], {}, step[:block]]
          else
            declarations.instance_exec(nil, &step[:block])
          end
        end
        signature_of(declarations.calls)
      end

      # +value+ as a String that's the same in every process
      def signature_of(value)
        case value
        when nil, true, false, Symbol, String, Numeric
          value.inspect
        when Array
          "[#{value.map { |v| signature_of(v) }.join(',')}]"
        when Hash
          "{#{value.map { |k, v| "#{signature_of(k)}=>#{signature_of(v)}" }.join(',')}}"
        when Module
          "#{value.class.name}(#{value.name})"
        when Proc
          "Proc(#{proc_location(value)})"
        else
          "#{value.class.name}(#{value.to_json})"
        end
      end

      # Where +proc+ is defined, relative to the app, as its root differs
      # between deploys that share a cache
      def proc_location(proc)
        file, line = proc.source_location
        return if !file

        root = (Rails.root.to_s if defined?(Rails) && Rails.respond_to?(:root) && Rails.root)
        file = file.delete_prefix("#{root}/") if root
        "#{file}:#{line}"
      end
    end

  end
end
