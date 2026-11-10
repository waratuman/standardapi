# Mirrors StandardAPI::Includes#check_include_when: the attributes of +model+
# its ACL wheres permit an +eq+ on, each compared with its value as
# application/_record renders it
definitions = json_schema_definitions(model)

json.set! 'type', 'object'
json.set! 'properties' do
  # Jbuilder leaves out a block that sets nothing
  json.merge!({})
  json_schema_wheres(model).each do |key, operators|
    next if !model.attribute_names.include?(key)
    next if operators != :all && !operators.include?('eq')

    json.set! key, definitions[key] ? json_schema_attribute_read(model, definitions[key]) : {}
  end
end
json.set! 'additionalProperties', false
