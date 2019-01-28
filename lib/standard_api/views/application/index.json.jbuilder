if !includes.empty? && can_cache?(model, includes)
  partial = model_partial(model)
  record_name = partial.split('/').last.to_sym
  locals = { record_name => nil, :includes => includes }

  json.cache_collection! instance_variable_get("@#{model.model_name.plural}"), key: proc { |record| cache_key(record, includes) } do |record|
    locals[record_name] = record
    json.partial! partial, locals
  end
else
  if !includes.empty?
    instance_variable_set("@#{model.model_name.plural}", instance_variable_get("@#{model.model_name.plural}").preload(includes.keys))
  end

  json.array! instance_variable_get("@#{model.model_name.plural}"), partial: model_partial(model), as: model_partial(model).split('/').last, includes: includes
end
