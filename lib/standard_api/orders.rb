module StandardAPI
  # Included in StandardAPI::Controller. What can be ordered by is what each
  # model's Policy declares +orderable+, record_policy(model).orderable.
  module Orders

    private

    # Sanitize +orders+ against what +policy+, a Policy::Record, makes
    # orderable on its model. Ordering through an association (ie. +:owner+)
    # is checked against what the associated model's Policy makes orderable:
    #
    #   sanitize_orders({ owner: { name: :asc } }, record_policy(Property))
    #   # => { owner: { name: :asc } } if Property's Policy makes owner
    #   #    orderable and Owner's makes name orderable
    def sanitize_orders(orders, policy)
      return nil if orders.nil?

      model = policy.model
      permit = policy.orderable.map(&:to_s)
      permitted = []

      case orders
      when Hash, ActionController::Parameters
        orders.each do |key, value|
          if key.to_s.count('.') == 1
            key2, key3 = *key.to_s.split('.')
            permitted << sanitize_orders({key2.to_sym => { key3.to_sym => value } }, policy)
          elsif permit.include?(key.to_s)
            association = model.reflect_on_association(key)

            value = if association
              # A polymorphic association has no single Policy to check against
              raise(StandardAPI::UnpermittedParameters.new([orders])) if association.polymorphic?
              sanitize_orders(value, record_policy(association.klass))
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
          order = sanitize_orders(order, policy)
          if order.is_a?(Array)
            permitted += order
          else
            permitted << order
          end
        end
      else
        if orders.to_s.count('.') == 1
          key, value = *orders.to_s.split('.')
          permitted = sanitize_orders({key.to_sym => value.to_sym}, policy)
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

    # The names of the columns and associations +orders+, as #sanitize_orders
    # returns them, orders by
    def order_names(orders)
      case orders
      when nil then []
      when Array then orders.flat_map { |order| order_names(order) }
      when Hash then orders.keys.map(&:to_s)
      else [orders.to_s]
      end
    end

  end
end
