# An object of the names +permit+ lists, each to its direction, or to the
# order of the association it names
json.set! 'type', 'object'
json.set! 'properties' do
  permit.each do |entry|
    if entry.is_a?(Hash)
      entry.each do |name, subpermit|
        json.set! name.to_s do
          json.partial!('application/json_schema/order', permit: subpermit, model: nil, defs: defs)
        end
      end
    elsif (association = model&.reflect_on_association(entry.to_s)) && !association.polymorphic?
      json.set! entry.to_s, json_schema_order_ref(defs, association.klass)
    else
      json.set! entry.to_s, json_schema_direction
    end
  end
end
json.set! 'additionalProperties', false
json.set! 'minProperties', 1
