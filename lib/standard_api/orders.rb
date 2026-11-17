module StandardAPI
  # Included in StandardAPI::Controller. What can be ordered by is what each
  # model's Policy declares +orderable+.
  module Orders

    private

    # The names of the attributes and associations of +klass+ its Policy
    # declares +orderable+, or [] without a Policy
    def orders_for(klass)
      # TODO: Remove this check in 10.0
      if respond_to?(method = "#{klass.model_name.singular}_orders", true)
        raise StandardAPI::InvalidConfiguration, "#{ self.method(method).owner.name }##{ method } is not supported, declare what can be ordered by with orderable in #{ klass.name }'s Policy instead"
      end

      policy = model_policy(klass)
      policy ? policy.orderable : []
    end

    # Sanitize +orders+ of +model+ against +permit+, the names of the columns
    # and associations of +model+ that can be ordered by. Ordering through an
    # association (ie. +:owner+) is checked against what the associated
    # model's Policy makes orderable:
    #
    #   sanitize_orders({ owner: { name: :asc } }, ['owner'], Property)
    #   # => { owner: { name: :asc } } if OwnerPolicy makes name orderable
    def sanitize_orders(orders, permit, model)
      return nil if orders.nil?

      permit = permit.map(&:to_s)
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
              # A polymorphic association has no single Policy to check against
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
