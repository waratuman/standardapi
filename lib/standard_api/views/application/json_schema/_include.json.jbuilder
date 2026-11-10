# Mirrors StandardAPI::Includes#sanitize_includes: an object of the
# associations +permit+ lists (application/json_schema/_include_object), a
# name, or an Array of either. +model+ is nil under a polymorphic
# association, where a +where+ can't be checked.
#
# With a +name+, the object is rendered into $defs with the options (+where+,
# +order+, +limit+, +distinct+, +distinct_on+, +when+) that apply to included
# records. The top level, without one, has no options and is inline.
names = permit.keys.map(&:to_s) - StandardAPI::Controller::RESERVED_INCLUDE_KEYS
name_schema = { 'type' => 'string', 'enum' => names }
object = if name
  json_schema_ref(defs, name, 'include_object', permit: permit, model: model, prefix: name, options: true)
end

include_object = lambda do
  json.child! do
    if object
      json.merge! object
    else
      json.partial!('application/json_schema/include_object', permit: permit, model: model, defs: defs,
        prefix: model && json_schema_name(model, ''), options: false)
    end
  end
end

json.set! 'anyOf' do
  include_object.call
  json.child! { json.merge! name_schema }
  json.child! do
    json.set! 'type', 'array'
    json.set! 'items' do
      json.set! 'anyOf' do
        json.child! { json.merge! name_schema }
        include_object.call
      end
    end
  end
end
