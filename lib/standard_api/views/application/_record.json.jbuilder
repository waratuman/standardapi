record.class.columns.each do |column|
  # Skip if attribute is included in excludes
  next if defined?(excludes) && excludes[record.model_name.singular.to_sym].try(:find) { |x| x.to_s == column.name.to_s }
  
  if column.type == :binary
    json.set! column.name.to_s, record.send(column.name)&.unpack('H*')&.first
  else
    json.set! column.name.to_s, record.send(column.name)
  end
end

includes.each do |inc, subinc|
  next if ["limit", "offset", "order", "when", "where", "distinct", "distinct_on"].include?(inc)

  case association = record.class.reflect_on_association(inc)
  when ActiveRecord::Reflection::AbstractReflection
    if association.collection?
      can_cache = can_cache_relation?(record, inc, subinc)
      json.set! inc do
        json.cache_if!(can_cache, can_cache ? association_cache_key(record, inc, subinc) : nil) do
          partial = model_partial(association.klass)

          # TODO limit causes preloaded assocations to reload
          sub_records = record.send(inc)

          sub_records = sub_records.limit(subinc['limit']) if subinc['limit']
          sub_records = sub_records.offset(subinc['offset']) if subinc['offset']
          sub_records = sub_records.reorder(subinc['order']) if subinc['order']
          sub_records = sub_records.filter(subinc['where']) if subinc['where']
          sub_records = sub_records.distinct if subinc['distinct']
          sub_records = sub_records.distinct_on(subinc['distinct_on']) if subinc['distinct_on']

          json.array! sub_records, partial: partial, as: partial.split('/').last, locals: { includes: subinc }
        end
      end
    else
      can_cache = can_cache_relation?(record, inc, subinc)
      if association.is_a?(ActiveRecord::Reflection::BelongsToReflection)
        can_cache = can_cache && !record.send(association.foreign_key).nil?
      end
      json.set! inc do
        json.cache_if!(can_cache, can_cache ? association_cache_key(record, inc, subinc) : nil) do
          value = record.send(inc)
          if value.nil?
            json.null!
          else
            partial = model_partial(value)
            json.partial! partial, partial.split('/').last.to_sym => value, includes: subinc
          end
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
