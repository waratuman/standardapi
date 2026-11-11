# Mirrors StandardAPI::Orders#sanitize_orders: a name +permit+ lists, an
# object of them (application/json_schema/_order_object), or an Array of
# either. +model+ is nil under a Hash in +permit+. An empty +permit+ accepts
# nothing.
permit = Array(permit).flatten

if permit.empty?
  json.set! 'not', {}
else
  name_schema = { 'type' => 'string', 'enum' => json_schema_order_names(model, permit) }

  json.set! 'anyOf' do
    json.child! { json.merge! name_schema }
    json.child! do
      json.partial!('application/json_schema/order_object', permit: permit, model: model, defs: defs)
    end
    json.child! do
      json.set! 'type', 'array'
      json.set! 'items' do
        json.set! 'anyOf' do
          json.child! { json.merge! name_schema }
          json.child! do
            json.partial!('application/json_schema/order_object', permit: permit, model: model, defs: defs)
          end
        end
      end
    end
  end
end
