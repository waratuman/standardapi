model.attributes.each do |name, value|
  json.set! name, value
end

includes.each do |inc, subinc|
  association = model.class.reflect_on_association(inc)
  if association.klass < ActiveRecord::Base
    json.set! inc do
      collection = [:has_many, :has_and_belongs_to_many].include?(association.macro)

      partial = if lookup_context.exists?(association.klass.model_name.element, controller_name)
        # [controller_name, association.klass.model_name.element].join('/')
        association.klass.model_name.element
      else
        # 'application/model'
        'model'
      end

      if collection
        json.array! model.send(inc), partial: partial, as: :model, locals: { includes: subinc }
      else
        json.partial! partial, model: model.send(inc), includes: subinc
      end
    end
  else
    json.set! inc, model.send(inc)
  end
end

if !model.errors.blank?
  json.set! 'errors', model.errors.to_h
end