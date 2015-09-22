record.attributes.each do |name, value|
  # Skip if attribute is included in excludes
  next if defined?(excludes) && excludes[record.model_name.singular.to_sym].try(:find) { |x| x.to_s == name.to_s }
  json.set! name, value
end

includes.each do |inc, subinc|
  next if ['where', 'order'].include?(inc.to_s)

  association = record.class.reflect_on_association(inc)
  if association
    collection = [:has_many, :has_and_belongs_to_many].include?(association.macro)

    if collection
      partial = model_partial(association.klass)
      json.set! inc do
        json.array! record.send(inc), partial: partial, as: partial.split('/').last, locals: { includes: subinc }
      end
    else

      if record.send(inc).nil?
        json.set! inc, nil
      else
        partial = model_partial(record.send(inc))
        json.set! inc do
          json.partial! partial, partial.split('/').last.to_sym => record.send(inc), includes: subinc
        end
      end
    end

  else

    if record.send(inc).nil?
      json.set! inc, nil
    elsif record.send(inc).is_a?(ActiveModel::Model)
      json.set! inc do
        partial = model_partial(record.send(inc))
        json.partial! partial, partial.split('/').last.to_sym => record.send(inc), includes: subinc
      end
    else
      # TODO: Test
      json.set! inc, record.send(inc).as_json
    end

  end
  
end

if !record.errors.blank?
  json.set! 'errors', record.errors.to_hash
end