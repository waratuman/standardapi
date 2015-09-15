records = @records if !records

json.array! records, partial: 'application/record', as: :record, includes: includes
