excluded = resolve_excludes(photo, local_assigns[:excludes])

json.set! :id,          photo.id          unless excluded[:id] == true
json.set! :account_id,  photo.account_id  unless excluded[:account_id] == true
json.set! :property_id, photo.property_id unless excluded[:property_id] == true
json.set! :format,      photo.format      unless excluded[:format] == true
json.set! :created_at,  photo.created_at  unless excluded[:created_at] == true
json.set! :template,    'photos/_photo'

if includes[:account] && excluded[:account] != true
  json.set! :account do
    if photo.account
      json.partial! 'application/record', record: photo.account,
        includes: includes[:account], excludes: sub_excludes(excluded, :account)
    else
      json.null!
    end
  end
end
