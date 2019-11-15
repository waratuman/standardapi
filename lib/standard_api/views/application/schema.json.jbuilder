json.set! 'columns' do
  model.columns.each do |column|
    json.set! column.name, {
      type: json_column_type(column.sql_type),
      default: column.default || column.default_function,
      primary_key: column.name == model.primary_key,
      null: column.null,
      array: column.array,
      comment: column.comment
    }
  end
end

json.set! 'limit', resource_limit
json.set! 'comment', model.connection.table_comment(model.table_name)
