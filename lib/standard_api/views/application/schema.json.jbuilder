mapping = {
    'timestamp without time zone' => 'datetime',
    'time without time zone' => 'datetime',
    'text' => 'string',
    'json' => 'hash',
    'integer' => 'integer',
    'character varying(255)' => 'string',
    'character varying(128)' => 'string',
    'character varying(50)' => 'string',
    'character varying' => 'string',
    'jsonb' => 'hash',
    'inet' => 'string', #TODO: should be inet
    'hstore' => 'hash',
    'date' => 'datetime',
    'numeric(16,2)' => 'decimal',
    'numeric' => 'decimal',
    'double precision' => 'decimal',
    'ltree' => 'string',
    'boolean' => 'boolean',
    'geometry' => 'hash'
}

model.columns.each do |column|
  json.set! column.name, {
    type: mapping[column.sql_type],
    primary_key: column.name == @model.primary_key,
    null: column.null,
    array: column.array
  }
end