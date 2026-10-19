module StandardAPI
  module Orders

    # Sanitize +orders+ against +permit+. When +model+ and a block are given,
    # ordering through an association permitted by name alone (ie. +:owner+)
    # is checked against the associated model's permitted orders, which the
    # block returns for a given model:
    #
    #   sanitize({ owner: { name: :asc } }, [:owner], Property) { |m| [:name] }
    #   # => { owner: { name: :asc } }
    def self.sanitize(orders, permit, model = nil, &acl)
      return nil if orders.nil?

      permit = [permit] if !permit.is_a?(Array)
      permit = permit.flatten.map { |x| x.is_a?(Hash) ? x.with_indifferent_access : x.to_s }
      permitted = []

      case orders
      when Hash, ActionController::Parameters
        orders.each do |key, value|
          if key.to_s.count('.') == 1
            key2, key3 = *key.to_s.split('.')
            permitted << sanitize({key2.to_sym => { key3.to_sym => value } }, permit, model, &acl)
          elsif permit.include?(key.to_s)
            association = model.reflect_on_association(key) if acl && model
            value = if association && !association.polymorphic?
              sanitize(value, acl.call(association.klass), association.klass, &acl)
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
          order = sanitize(order, permit, model, &acl)
          if order.is_a?(Array)
            permitted += order
          else
            permitted << order
          end
        end
      else
        if orders.to_s.count('.') == 1
          key, value = *orders.to_s.split('.')
          permitted = sanitize({key.to_sym => value.to_sym}, permit, model, &acl)
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
