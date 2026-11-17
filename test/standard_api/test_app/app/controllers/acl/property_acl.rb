module PropertyACL

  # Attributes allowed to be updated
  def attributes(record = nil)
    [ :name,
      :aliases,
      :description,
      :constructed,
      :size,
      :active,
      :numericality
      # :photos_attributes,
      # { photos_attributes: [ :id, :account_id, :property_id, :format] }
    ]
  end

  # Sub resources allowed to be included in the response
  # Sub resourced allowed to be set during create / update / delete if a user is
  # allowed to ....
  # only add to and from the relation, can also create or update the subresource
  def nested
    [ :photos, :accounts ]
  end

end
