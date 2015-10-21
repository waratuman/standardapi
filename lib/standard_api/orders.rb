module StandardAPI
  module Orders

    def self.sanitize(orders, permit)
      return nil if orders.nil?

      permit = [permit] if !permit.is_a?(Array)
      permit = permit.flatten.map { |x| x.is_a?(Hash) ? x.with_indifferent_access : x.to_s }
      permitted = []

      case orders
      when Hash
        orders.each do |key, value|
          if key.to_s.count('.') == 1
            key2, key3 = *key.to_s.split('.')
            permitted << sanitize({key2.to_sym => { key3.to_sym => value } }, permit)
          elsif permit.include?(key.to_s)
            value = value.symbolize_keys if value.is_a?(Hash)
            permitted << { key.to_sym => value }
          elsif permit.find { |x| x.is_a?(Hash) && x.has_key?(key.to_s) }
            subpermit = permit.find { |x| x.is_a?(Hash) && x.has_key?(key.to_s) }[key.to_s]
            sanitized_value = sanitize(value, subpermit)
            permitted << { key.to_sym => sanitized_value }
          else
            raise(ActionDispatch::ParamsParser::ParseError.new("Invalid Ordering #{orders.inspect}", nil))
          end
        end
      when Array
        orders.each do |order|
          order = sanitize(order, permit)
          if order.is_a?(Array)
            permitted += order
          else
            permitted << order
          end
        end
      else

        if orders.to_s.count('.') == 1
          key, value = *orders.to_s.split('.')
          permitted = sanitize({key.to_sym => value.to_sym}, permit)
        elsif permit.include?(orders.to_s)
          permitted = orders
        else
          raise(ActionDispatch::ParamsParser::ParseError.new("Invalid Ordering #{orders.inspect}", nil))
        end
      end

      if permitted.is_a?(Array) && permitted.length == 1
        permitted.first
      else
        permitted
      end

      # permitted
    end

  end
end
