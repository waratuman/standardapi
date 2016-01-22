json.set! :id,          photo.id
json.set! :account_id,  photo.account_id
json.set! :property_id, photo.property_id
json.set! :format,      photo.format
json.set! :template,    'photos/_photo'

if includes[:account]
  json.set! :account do
    if photo.account
      json.partial! 'application/record', record: photo.account, includes: includes[:account]
    else
      json.null!
    end
  end
end
