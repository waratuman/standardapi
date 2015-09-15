record = @record if !record

# partial = if lookup_context.exists?(association.klass.model_name.element, controller_name)
#   association.klass.model_name.element
# else
#   'record'
# end

json.partial! 'application/record', record: record, includes: includes
