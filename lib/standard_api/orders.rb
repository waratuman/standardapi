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

      orders = self.send(method)
      permits = Array(orders).flatten.select { |x| x.is_a?(Hash) || x.is_a?(ActionController::Parameters) }
      permits.flat_map(&:keys).each do |name|
        # A polymorphic association has no single ACL to permit its columns
        # in, so they can still be permitted here
        association = klass.reflect_on_association(name)
        next if !association || association.polymorphic?

        raise StandardAPI::InvalidConfiguration, "#{ klass.name }ACL#orders permitting columns of #{ name } is not supported, permit :#{ name } in #{ klass.name }ACL#orders and its columns in #{ association.klass.name }ACL#orders instead"
      end

      orders
    end

    # Sanitize +orders+ of +model+ against +permit+. Ordering through an
    # association permitted by name alone (ie. +:owner+) is checked against the
    # orders the ACL permits on the associated model:
    #
    #   sanitize_orders({ owner: { name: :asc } }, [:owner], Property)
    #   # => { owner: { name: :asc } } if owner_orders includes :name
    #
    # +model+ is nil when there is no single model, ie. through a polymorphic
    # association, in which case orders are checked against +permit+ alone.
    def sanitize_orders(orders, permit, model)
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
