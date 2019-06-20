record.attributes.each do |name, value|
  # Skip if attribute is included in excludes
  next if defined?(excludes) && excludes[record.model_name.singular.to_sym].try(:find) { |x| x.to_s == name.to_s }
  json.set! name, value
end

includes.each do |inc, subinc|
  next if ["limit", "offset", "order", "when", "where"].include?(inc)

  case association = record.class.reflect_on_association(inc)
  when ActiveRecord::Reflection::HasManyReflection, ActiveRecord::Reflection::HasAndBelongsToManyReflection, ActiveRecord::Reflection::ThroughReflection
    can_cache = can_cache_relation?(record.class, inc, subinc)
    json.cache_if!(can_cache, can_cache ? association_cache_key(record, inc, subinc) : nil) do
      partial = model_partial(association.klass)
      json.set! inc do
        # TODO limit causes preloaded assocations to reload
        if subinc.keys.any? { |x| ["limit", "offset", "order", "when", "where"].include?(x) }
          if subinc["distinct"]
            json.array! record.send(inc).filter(subinc["where"]).limit(subinc["limit"]).sort(subinc["order"]).distinct_on(subinc["distinct"]), partial: partial, as: partial.split('/').last, locals: { includes: subinc }
          else
            json.array! record.send(inc).filter(subinc["where"]).limit(subinc["limit"]).sort(subinc["order"]).distinct, partial: partial, as: partial.split('/').last, locals: { includes: subinc }
          end
        else
          json.array! record.send(inc), partial: partial, as: partial.split('/').last, locals: { includes: subinc }
        end
      end
    end
  
  when ActiveRecord::Reflection::BelongsToReflection, ActiveRecord::Reflection::HasOneReflection
    can_cache = can_cache_relation?(record.class, inc, subinc)
    if association.is_a?(ActiveRecord::Reflection::BelongsToReflection)
      can_cache = can_cache && !record.send(association.foreign_key).nil?
    end
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
  errs = record.errors.to_hash
  errs.default_proc = nil
  json.set! 'errors', errs
end
