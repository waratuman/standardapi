module StandardAPI
  # Included in StandardAPI::Controller, so the ACL +orders+ methods are
  # called on the controller.
  module Orders

    private

    # The orders the ACL permits on +klass+, or [] if it has none
    def orders_for(klass)
      return [] if !self.respond_to?("#{klass.model_name.singular}_orders", true)

      orders = self.send("#{klass.model_name.singular}_orders")
      Array(orders).flatten.grep(Hash).flat_map(&:keys).each do |name|
        association = klass.reflect_on_association(name)
        nested_acl = if association && !association.polymorphic?
          "#{association.klass.name}ACL#orders"
        else
          "the #{name} ACL's orders"
        end

        logger&.warn <<~NOTE.strip_heredoc
          DEPRECATION WARNING: #{ klass.name }ACL#orders permitting columns of #{ name } has been deprecated, permit :#{ name } in #{ klass.name }ACL#orders and its columns in #{ nested_acl } instead
        NOTE
      end

      orders
    end

    # Sanitize +orders+ through an association to +klass+ against +permit+.
    # ActiveRecord::Sort only orders one association deep, so only the columns
    # of +klass+ in +permit+ are permitted.
    def sanitize_association_orders(orders, permit, klass)
      permit = Array.wrap(permit).flatten.select { |x| klass.column_names.include?(x.to_s) }
      sanitize_orders(orders, permit)
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
            value = if association && !association.polymorphic?
              sanitize_association_orders(value, orders_for(association.klass), association.klass)
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
            sanitized_value = if association && !association.polymorphic?
              sanitize_association_orders(value, subpermit, association.klass)
            else
              sanitize_orders(value, subpermit)
            end
            permitted << { key.to_sym => sanitized_value }
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
