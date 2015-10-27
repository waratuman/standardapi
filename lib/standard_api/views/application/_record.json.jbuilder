record.attributes.each do |name, value|
  # Skip if attribute is included in excludes
  next if defined?(excludes) && excludes[record.model_name.singular.to_sym].try(:find) { |x| x.to_s == name.to_s }
  json.set! name, value
end

includes.each do |inc, subinc|
  next if [:where, :order, :limit].include?(inc.to_sym)
  
  case association = record.class.reflect_on_association(inc)
  when ActiveRecord::Reflection::HasManyReflection, ActiveRecord::Reflection::HasAndBelongsToManyReflection
    can_cache = can_cache_relation?(record.class, inc, subinc)
    json.cache_if!(can_cache, can_cache ? association_cache_key(record, inc, subinc) : nil) do
      partial = model_partial(association.klass)
      json.set! inc do
        json.array! record.send(inc).filter(subinc[:where]).limit(subinc[:limit]).order(subinc[:order]), partial: partial, as: partial.split('/').last, locals: { includes: subinc }
      end
    end
  
  when ActiveRecord::Reflection::BelongsToReflection, ActiveRecord::Reflection::HasOneReflection
    can_cache = can_cache_relation?(record.class, inc, subinc)
    json.cache_if!(can_cache, can_cache ? association_cache_key(record, inc, subinc) : nil) do
      value = record.send(inc)
      if value.nil?
        json.set! inc, nil
      else
        partial = model_partial(value)
        json.set! inc do
          json.partial! partial, partial.split('/').last.to_sym => value, includes: subinc
        end
      end
    end
    
  else
    if record.respond_to?(inc)
      value = record.send(inc)
      if value.nil?
        json.set! inc, nil
      elsif value.is_a?(ActiveModel::Model)
        json.set! inc do
          partial = model_partial(value)
          json.partial! partial, partial.split('/').last.to_sym => value, includes: subinc
        end
      else
        json.set! inc, value.as_json
      end
    end
  end
  
end

if !record.errors.blank?
  json.set! 'errors', record.errors.to_hash
end