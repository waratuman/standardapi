if !defined?(records)
  records = instance_variable_get("@#{model.model_name.plural}")
end

partial = model_partial(model)
partial_record_name = partial.split('/').last.to_sym

if !includes.empty? && can_cache?(model, includes)
  json.cache_collection! records, key: proc { |record| cache_key(record, includes) } do |record|
    json.partial!(partial, includes: includes, partial_record_name => record)
  end
else
  json.array!(records) do |record|
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

    json.partial!(partial, includes: sub_includes, partial_record_name => record)
  end
end
