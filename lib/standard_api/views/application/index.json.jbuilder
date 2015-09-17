json.array! instance_variable_get("@#{model.model_name.plural}"), partial: model_partial(model), as: :record, includes: includes
