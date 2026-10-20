module StandardAPI
  module Orders

    # The orders +acl+, ie. a controller, permits on +klass+, or [] if it
    # has none
    def self.orders_for(acl, klass)
      return [] if !acl.respond_to?("#{klass.model_name.singular}_orders", true)

      orders = acl.send("#{klass.model_name.singular}_orders")
      Array(orders).flatten.grep(Hash).flat_map(&:keys).each do |name|
        association = klass.reflect_on_association(name)
        nested_acl = if association && !association.polymorphic?
          "#{association.klass.name}ACL#orders"
        else
          "the #{name} ACL's orders"
        end

        acl.logger&.warn <<~NOTE.strip_heredoc
          DEPRECATION WARNING: #{ klass.name }ACL#orders permitting columns of #{ name } has been deprecated, permit :#{ name } in #{ klass.name }ACL#orders and its columns in #{ nested_acl } instead
        NOTE
      end

      orders
    end

    # Sanitize +orders+ against +permit+. When +model+ and +acl+ are given,
    # ordering through an association permitted by name alone (ie. +:owner+)
    # is checked against the orders +acl+ permits on the associated model:
    #
    #   sanitize({ owner: { name: :asc } }, [:owner], Property, controller)
    #   # => { owner: { name: :asc } } if controller.owner_orders includes :name
    def self.sanitize(orders, permit, model = nil, acl = nil)
      return nil if orders.nil?

      permit = [permit] if !permit.is_a?(Array)
      permit = permit.flatten.map { |x| x.is_a?(Hash) ? x.with_indifferent_access : x.to_s }
      permitted = []

      case orders
      when Hash, ActionController::Parameters
        orders.each do |key, value|
          if key.to_s.count('.') == 1
            key2, key3 = *key.to_s.split('.')
            permitted << sanitize({key2.to_sym => { key3.to_sym => value } }, permit, model, acl)
          elsif permit.include?(key.to_s)
            association = model.reflect_on_association(key) if acl && model
            value = if association && !association.polymorphic?
              sanitize(value, orders_for(acl, association.klass), association.klass, acl)
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
            sanitized_value = sanitize(value, subpermit)
            permitted << { key.to_sym => sanitized_value }
          else
            raise(StandardAPI::UnpermittedParameters.new([orders]))
          end
        end
      when Array
        orders.each do |order|
          order = sanitize(order, permit, model, acl)
          if order.is_a?(Array)
            permitted += order
          else
            permitted << order
          end
        end
      else
        if orders.to_s.count('.') == 1
          key, value = *orders.to_s.split('.')
          permitted = sanitize({key.to_sym => value.to_sym}, permit, model, acl)
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
