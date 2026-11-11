# The params #index and #calculate accept: the +where+, +order+ and +include+
# the ACL permits, +limit+, +offset+, +distinct+, the model's columns to
# +group_by+, and the unchecked +distinct_on+, +join+ and +select+. The where,
# order and include of each model reachable through a permitted association
# are rendered into $defs.
defs = {}
order = json_schema_orders(model) | json_schema_required_orders
include_permit = json_schema_includes(model)

json.set! '$schema', StandardAPI::Helpers::JSONSchema::DIALECT
json.set! 'title', model.model_name.human.pluralize
json.set! 'type', 'object'
json.set! 'properties' do
  if json_schema_wheres(model).any?
    json.set! 'where', json_schema_ref(defs, json_schema_name(model, 'Where'), 'where', model: model)
  end

  if order.any?
    json.set! 'order' do
      json.partial!('application/json_schema/order', permit: order, model: model, defs: defs)
    end
  end

  if include_permit.any?
    json.set! 'include' do
      json.partial!('application/json_schema/include', permit: include_permit, model: model, defs: defs, name: nil)
    end
  end

  json.set! 'limit', {
    'type' => 'integer',
    'minimum' => 0,
    'maximum' => resource_limit,
    'default' => default_limit
  }.compact
  json.set! 'offset', { 'type' => 'integer', 'minimum' => 0 }
  json.set! 'distinct', { 'type' => 'boolean' }

  # Mirrors Controller#group_by, which only accepts the model's columns
  column_name = { 'type' => 'string', 'enum' => model.column_names }
  json.set! 'group_by', {
    'anyOf' => [column_name, { 'type' => 'array', 'items' => column_name }],
    'description' => 'Columns of the model to group by. #calculate returns an object keyed by group.'
  }

  # Used by #resources and #calculate_selects, but not checked by the ACL
  json.set! 'distinct_on', json_schema_unchecked(json_schema_columns, 'Columns to select distinct rows on, passed to `distinct_on`. Takes precedence over `distinct`.')
  json.set! 'join', json_schema_unchecked(
    { 'type' => 'string', 'enum' => model.reflect_on_all_associations.map { |a| a.name.to_s } },
    'An association to inner join, passed to `joins`.'
  )
  json.set! 'select', json_schema_unchecked(json_schema_select, 'The calculations #calculate returns.')
end

# #index needs a limit when there is no default; #calculate, which takes a
# select, doesn't
if resource_limit && !default_limit
  json.set! 'anyOf', [{ 'required' => ['limit'] }, { 'required' => ['select'] }]
end

# Rendering a def can refer to more, so render until none are left
if defs.any?
  json.set! '$defs' do
    rendered = 0
    while rendered < defs.size
      name = defs.keys[rendered]
      rendered += 1
      json.set! name do
        json.partial!(defs[name][:partial], defs[name][:locals].merge(defs: defs))
      end
    end
  end
end
