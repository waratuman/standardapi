record = @record if !record

json.partial! 'application/model', record: record, includes: includes
