record = @record if !record

json.partial! 'application/record', record: record, includes: includes
