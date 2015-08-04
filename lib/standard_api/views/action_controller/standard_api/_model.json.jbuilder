model.attributes.each do |name, value|
  json.set! name, value
end

includes.each do |inc|
  if model.class.reflect_on_association(inc).klass.is_a?(ActiveModel)
    json.set! inc do
      json.partial! 'action_controller/standard_api/_model', locals: { model: model.send(inc) }
    end
  else
    json.set! inc, model.send(inc)
  end
end

if model.errors
  json.set! 'errors', model.errors.to_h
end