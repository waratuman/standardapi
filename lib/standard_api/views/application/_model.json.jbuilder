model.attributes.each do |name, value|
  json.set! name, value
end

includes.each do |inc, subinc|
  if model.class.reflect_on_association(inc).klass < ActiveRecord::Base
    json.set! inc do
      collection = [:has_many, :has_and_belongs_to_many].include?(model.class.reflect_on_association(inc).macro)
      if collection
        json.array! model.send(inc), partial: 'application/model', as: :model, locals: { includes: subinc }
      else
        json.partial! 'application/model', model: model.send(inc), includes: subinc
      end
    end
  else
    json.set! inc, model.send(inc)
  end
end

if !model.errors.blank?
  json.set! 'errors', model.errors.to_h
end