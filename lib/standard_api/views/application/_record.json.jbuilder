excluded = resolve_excludes(record, local_assigns[:excludes])
record.attribute_names.each do |name|
  next if excluded[name] == true

  serialize_attribute(json, record, name, record.type_for_attribute(name).type)
end

includes.each do |inc, subinc|
  next if ["limit", "offset", "order", "when", "where", "distinct", "distinct_on"].include?(inc)
  next if excluded[inc] == true

  sub_excluded = sub_excludes(excluded, inc)

  case association = record.class.reflect_on_association(inc)
  when ::ActiveRecord::Reflection::AbstractReflection
    if association.collection?
      can_cache = can_cache_relation?(record, inc, subinc, excludes: sub_excluded)
      json.set! inc do
        json.cache_if!(can_cache, can_cache ? association_cache_key(record, inc, subinc) : nil) do
          partial = model_partial(association.klass)

          # TODO limit causes preloaded assocations to reload
          sub_records = record.send(inc)

          # Apply the controller's mask for the included association's table, so
          # row-level scoping (e.g. hiding restricted rows) is enforced on
          # includes the same as on the top-level resource.
          if respond_to?(:mask)
            sub_records = sub_records.filter(mask[association.klass.table_name.to_sym])
          end

          sub_records = sub_records.limit(subinc['limit']) if subinc['limit']
          sub_records = sub_records.offset(subinc['offset']) if subinc['offset']
          sub_records = sub_records.reorder(subinc['order']) if subinc['order']
          sub_records = sub_records.filter(subinc['where']) if subinc['where']
          sub_records = sub_records.distinct if subinc['distinct']
          sub_records = sub_records.distinct_on(subinc['distinct_on']) if subinc['distinct_on']

          json.array! sub_records, partial: partial, as: partial.split('/').last, locals: { includes: subinc, excludes: sub_excluded }
        end
      end
    else
      can_cache = can_cache_relation?(record, inc, subinc, excludes: sub_excluded)
      cache_key = nil

      if can_cache
        if association.is_a?(::ActiveRecord::Reflection::BelongsToReflection)
          can_cache = can_cache && !record.send(association.foreign_key).nil?
        end

        if can_cache
          cache_key = association_cache_key(record, inc, subinc)
          can_cache = cache_key.present?
        end
      end

      json.set! inc do
        json.cache_if!(can_cache, can_cache ? cache_key : nil) do
          value = record.send(inc)
          if value.nil?
            json.null!
          else
            partial = model_partial(value)
            json.partial! partial, partial.split('/').last.to_sym => value, includes: subinc, excludes: sub_excluded
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
          json.partial! partial, partial.split('/').last.to_sym => value, includes: subinc, excludes: sub_excluded
        end
      else
        json.set! inc, apply_excludes(value.as_json, sub_excluded)
      end
    end
  end

end

if !record.errors.blank?
  errs = record.errors.to_hash
  errs.default_proc = nil
  errs = reject_excluded_errors(errs, excluded)
  json.set! 'errors', errs
end
