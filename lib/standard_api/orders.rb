module StandardAPI
  # Included in StandardAPI::Controller, so the ACL +orders+ methods are
  # called on the controller.
  module Orders

    private

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

      # ACL orders list the columns and associations that can be ordered by;
      # what can be ordered by through an association is up to its own ACL
      orders = self.send(method)
      Array.wrap(orders).flatten.grep(Hash).flat_map(&:keys).each do |name|
        association = klass.reflect_on_association(name)
        instead = if association.nil?
          "permit :#{ name } instead"
        elsif association.polymorphic?
          "ordering through a polymorphic association is not supported"
        else
          "permit :#{ name } in #{ klass.name }ACL#orders and its columns in #{ association.klass.name }ACL#orders instead"
        end

        raise StandardAPI::InvalidConfiguration, "#{ klass.name }ACL#orders permitting #{ name } in a Hash is not supported, #{ instead }"
      end

      orders
    end

    # Sanitize +orders+ of +model+ against +permit+, the names of the columns
    # and associations of +model+ that can be ordered by. Ordering through an
    # association (ie. +:owner+) is checked against the orders the ACL permits
    # on the associated model:
    #
    #   sanitize_orders({ owner: { name: :asc } }, [:owner], Property)
    #   # => { owner: { name: :asc } } if owner_orders includes :name
    def sanitize_orders(orders, permit, model)
      return nil if orders.nil?

      permit = Array.wrap(permit).flatten.map(&:to_s)
      permitted = []

      case orders
      when Hash, ActionController::Parameters
        orders.each do |key, value|
          if key.to_s.count('.') == 1
            key2, key3 = *key.to_s.split('.')
            permitted << sanitize_orders({key2.to_sym => { key3.to_sym => value } }, permit, model)
          elsif permit.include?(key.to_s)
            association = model.reflect_on_association(key)

            value = if association
              # A polymorphic association has no single ACL to check against
              raise(StandardAPI::UnpermittedParameters.new([orders])) if association.polymorphic?
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
