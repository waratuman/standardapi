if !includes.empty?
  instance_variable_set("@#{model.model_name.plural}", preloadables(instance_variable_get("@#{model.model_name.plural}"), includes))
end

if !includes.empty? && can_cache?(model, includes)
  partial = model_partial(model)
  record_name = partial.split('/').last.to_sym
  locals = { record_name => nil, :includes => includes }

  json.cache_collection! instance_variable_get("@#{model.model_name.plural}"), key: proc { |record| cache_key(record, includes) } do |record|
    locals[record_name] = record
    json.partial! partial, locals
  end
else
  partial = model_partial(model)
  record_name = partial.split('/').last,
  json.array!(instance_variable_get("@#{model.model_name.plural}")) do |record|
    sub_includes = includes.select do |key, value|
      case value
      when Hash, ActionController::Parameters
        if value.has_key?('when')
          value['when'].all? { |k, v| record.send(k).as_json == v }
        else
          true
        end
      else
        true
      end
    end

    json.partial! partial, {
      record: record,
      record_name => record,
      includes: sub_includes
    }
  end
end
