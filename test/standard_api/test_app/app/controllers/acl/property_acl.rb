module PropertyACL

  # Attributes allowed to be updated
  def attributes
    [ :name,
      :aliases,
      :description,
      :constructed,
      :size,
      :active
      # :photos_attributes,
      # { photos_attributes: [ :id, :account_id, :property_id, :format] }
    ]
  end

  # Sortings allowed
  def sorts
    ["id", "name", "aliases", "description", "constructed", "size", "created_at", "active"]
  end

  # Sub resources allowed to be included in the response
  def includes
    [ :photos, :landlord, :english_name, :document ]
  end

  # Sub resourced allowed to be set during create / update / delete if a user is
  # allowed to ....
  # only add to and from the relation, can also create or update the subresource
  def nested
    [ :photos, :accounts ]
  end

end
