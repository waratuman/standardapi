json.set! '$schema', StandardAPI::JSONSchema::DIALECT
json.set! 'title', model.model_name.human
json.partial!('application/json_schema/read', model: model, includes: includes)
