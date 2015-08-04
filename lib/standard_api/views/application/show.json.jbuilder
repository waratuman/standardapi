model = @record if !model

json.partial! 'application/model', model: model, includes: includes
