record = @record if !record

json.partial! model_partial(model), record: record, includes: includes
