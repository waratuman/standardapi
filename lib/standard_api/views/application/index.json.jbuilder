records = @records if !records

json.array! models, partial: 'application/record', as: :record, includes: includes
