records = @records if !records

# partial = if lookup_context.exists?(association.klass.model_name.element, controller_name)
#   association.klass.model_name.element
# else
#   'record'
# end

json.array! records, partial: 'application/record', as: :record, includes: includes
