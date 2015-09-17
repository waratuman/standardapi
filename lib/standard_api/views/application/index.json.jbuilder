records = @records if !records

json.array! records, partial: model_partial(model), as: :record, includes: includes
