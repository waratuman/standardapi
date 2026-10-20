require 'concurrent/set'

module StandardAPI
  # Included in StandardAPI::Controller, so the ACL +orders+ methods are
  # called on the controller.
  module Orders

    # The deprecation warnings that have been logged
    @deprecations = Concurrent::Set.new

    def self.deprecations
      @deprecations
    end

    # Deprecated, include StandardAPI::Orders and use #sanitize_orders
    def self.sanitize(orders, permit)
      message = "StandardAPI::Orders.sanitize has been deprecated, include StandardAPI::Orders and use #sanitize_orders instead"
      Rails.logger&.warn("DEPRECATION WARNING: #{message}") if deprecations.add?(message)

      Object.new.extend(self).send(:sanitize_orders, orders, permit)
    end

    private

    # Log the deprecation warning +message+, once per process
    def deprecation_warning(message)
      return if !Orders.deprecations.add?(message)

      logger&.warn("DEPRECATION WARNING: #{message}")
    end

    # The ACL +orders+ method for +klass+, falling back to the one for its
    # base class (ie. an STI subclass), or nil if there is none
    def orders_method_for(klass)
      [klass, klass.base_class].uniq.map { |k| "#{k.model_name.singular}_orders" }.find do |method|
        self.respond_to?(method, true)
      end
    end

    # The orders the ACL permits on +klass+, or [] if it has none
    def orders_for(klass)
      return [] if !(method = orders_method_for(klass))

      orders = self.send(method)
      permits = Array(orders).flatten.select { |x| x.is_a?(Hash) || x.is_a?(ActionController::Parameters) }
      permits.flat_map(&:keys).each do |name|
        # A polymorphic association has no single ACL to permit its columns
        # in, so permitting them here is not deprecated
        association = klass.reflect_on_association(name)
        next if !association || association.polymorphic?

        deprecation_warning("#{ klass.name }ACL#orders permitting columns of #{ name } has been deprecated, permit :#{ name } in #{ klass.name }ACL#orders and its columns in #{ association.klass.name }ACL#orders instead")
      end

      orders
    end

    # Sanitize +orders+ against +permit+. When +model+ is given, ordering
    # through an association permitted by name alone (ie. +:owner+) is checked
    # against the orders the ACL permits on the associated model:
    #
    #   sanitize_orders({ owner: { name: :asc } }, [:owner], Property)
    #   # => { owner: { name: :asc } } if owner_orders includes :name
    def sanitize_orders(orders, permit, model = nil)
      return nil if orders.nil?

      permit = [permit] if !permit.is_a?(Array)
      permit = permit.flatten.map { |x| x.is_a?(Hash) ? x.with_indifferent_access : x.to_s }
      permitted = []

      case orders
      when Hash, ActionController::Parameters
        orders.each do |key, value|
          if key.to_s.count('.') == 1
            key2, key3 = *key.to_s.split('.')
            permitted << sanitize_orders({key2.to_sym => { key3.to_sym => value } }, permit, model)
          elsif permit.include?(key.to_s)
            association = model&.reflect_on_association(key)
            association = nil if association&.polymorphic?
            if association && !orders_method_for(association.klass)
              deprecation_warning("#{ model.name }ACL#orders permitting #{ key } without #{ association.klass.name }ACL#orders has been deprecated, permit the columns of #{ key } that can be ordered by in #{ association.klass.name }ACL#orders")
              association = nil
            end

            value = if association
              sanitize_orders(value, orders_for(association.klass), association.klass)
            else
              case value
              when Hash
                value
              when ActionController::Parameters
                value.permit([:asc, :desc]).to_h
              else
                value
              end
            end
            permitted << { key.to_sym => value }
          elsif permit.find { |x| (x.is_a?(Hash) || x.is_a?(ActionController::Parameters)) && x.has_key?(key.to_s) }
            subpermit = permit.find { |x| (x.is_a?(Hash) || x.is_a?(ActionController::Parameters)) && x.has_key?(key.to_s) }[key.to_s]
            association = model&.reflect_on_association(key)
            association = nil if association&.polymorphic?
            permitted << { key.to_sym => sanitize_orders(value, subpermit, association&.klass) }
          else
            raise(StandardAPI::UnpermittedParameters.new([orders]))
          end
        end
      when Array
        orders.each do |order|
          order = sanitize_orders(order, permit, model)
          if order.is_a?(Array)
            permitted += order
          else
            permitted << order
          end
        end
      else
        if orders.to_s.count('.') == 1
          key, value = *orders.to_s.split('.')
          permitted = sanitize_orders({key.to_sym => value.to_sym}, permit, model)
        elsif permit.include?(orders.to_s)
          permitted = orders
        else
          raise(StandardAPI::UnpermittedParameters.new([orders]))
        end
      end

      if permitted.is_a?(Array) && permitted.length == 1
        permitted.first
      else
        permitted
      end
    end

  end
end
