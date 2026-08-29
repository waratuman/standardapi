if !defined?(records)
  records = instance_variable_get("@#{model.model_name.plural}")
end

partial = model_partial(model)
partial_record_name = partial.split('/').last.to_sym

if !includes.empty? && can_cache?(model, includes)
  json.array! records,
    partial: partial,
    as: partial_record_name,
    locals: { includes: includes },
    cached: proc { |record| cache_key(record, includes) }
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
