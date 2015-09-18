json.array! instance_variable_get("@#{model.model_name.plural}"), partial: model_partial(model), as: model_partial(model).split('/').last, includes: includes
