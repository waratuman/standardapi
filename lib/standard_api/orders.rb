module StandardAPI
  module Orders

    # # :size                               => [:size]
    # # { :size => :asc }                   => [{:size => :asc}]
    # # { :size => :desc }                  => [{:size => :desc}]
    # # {:size => {:desc => :nulls_first}}  => [{:size => {:desc => :nulls_first}}]
    # # [:size, :id]                        => [:size, :id]
    # # { :size => :asc, :id => :desc }     => [{ :size => :asc, :id => :desc }]
    # # 'listings.size'                     => [{:listings => [:size]}]
    # # { 'listings.size' => :asc }         => [{:listings => [{:size => :asc}]}]
    # # { 'listings.size' => :desc }        => [{:listings => [{:size => :desc}]}]
    # # ['listings.size', 'property.id']    => [{:listings => [:size]}, {:property => [:id]}]
    # # { 'size' => :asc, 'property.id' => :desc } => [{:size => :asc}, {:property => [{:id => :desc}]}]
    # # { :size => {:asc => :nulls_first}, 'property.id' => {:desc => :null_last} } => [{:size => {:asc => :nulls_first}}, {:property => [{:id => {:desc => :nulls_first}}]}]
    # def self.normalize(orderings)
    #   return nil if orderings.nil?
    #   orderings = orderings.is_a?(Array) ? orderings : [orderings]
    #
    #   orderings.map! do |order|
    #     case order
    #     when Hash
    #       normalized = ActiveSupport::HashWithIndifferentAccess.new
    #       order.each do |key, value|
    #         key = key.to_s
    #         if key.index(".")
    #           relation, column = key.split('.').map(&:to_sym)
    #           normalized[relation] ||= []
    #           normalized[relation] << { column => value }
    #         elsif value.is_a?(Hash) && value.keys.first.to_s != 'desc' && value.keys.first.to_s != 'asc'
    #           normalized[key.to_sym] ||= []
    #           normalized[key.to_sym] << value
    #         else
    #           normalized[key.to_sym] = value
    #         end
    #       end
    #       normalized
    #     else
    #       order = order.to_s
    #       if order.index(".")
    #         relation, column = order.split('.').map(&:to_sym)
    #         { relation => [column] }
    #       else
    #         order.to_sym
    #       end
    #     end
    #   end
    # end

    def self.sanitize(orders, permit, normalized=false)
      return nil if orders.nil?

      permit = [permit] if !permit.is_a?(Array)
      permit = permit.flatten.map { |x| x.is_a?(Hash) ? x.with_indifferent_access : x.to_s }
      permitted = []

      case orders
      when Hash
        orders.each do |key, value|
          if permit.include?(key.to_s)
            value = value.symbolize_keys if value.is_a?(Hash)
            permitted = { key.to_sym => value }
          elsif permit.find { |x| x.is_a?(Hash) && x.has_key?(key.to_s) }
            subpermit = permit.find { |x| x.is_a?(Hash) && x.has_key?(key.to_s) }[key.to_s]
            sanitized_value = sanitize(value, subpermit, true)
            permitted = { key.to_sym => sanitized_value }
          else
            raise(ActionDispatch::ParamsParser::ParseError.new("Invalid Ordering #{orders.inspect}", nil))
          end
        end
      when Array
        orders.each { |order| permitted << sanitize(order, permit, true); }
      else
        if permit.include?(orders.to_s)
          permitted = orders
        else
          raise(ActionDispatch::ParamsParser::ParseError.new("Invalid Ordering #{orders.inspect}", nil))
        end
      end

      permitted
    end

  end
end