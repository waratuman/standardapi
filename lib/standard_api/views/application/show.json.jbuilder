# frozen_string_literal: true

if !defined?(record)
  record = instance_variable_get("@#{model.model_name.singular}")
end

partial = model_partial(model)
partial_record_name = partial.split('/').last.to_sym

json.partial!(partial, partial_record_name => record, includes: includes)
