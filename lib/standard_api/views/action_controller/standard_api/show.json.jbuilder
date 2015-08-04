model = @record if !model

json.partial! 'action_controller/standard_api/model', model: model, includes: includes
