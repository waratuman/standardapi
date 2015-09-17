json.partial! model_partial(model), record: instance_variable_get("@#{model.model_name.singular}"), includes: includes
