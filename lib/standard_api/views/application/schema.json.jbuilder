json.set! 'columns' do
  model.columns.each do |column|
    json.set! column.name, {
      type: json_column_type(column.sql_type),
      primary_key: column.name == model.primary_key,
      null: column.null,
      array: column.array
    }
  end
end

json.set! 'limit', resource_limit
