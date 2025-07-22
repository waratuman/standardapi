module PropertyACL

  # Attributes allowed to be updated
  def attributes
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

  # Orderings allowed
  def orders
    [
      "id",
      "name",
      "aliases",
      "description",
      "constructed",
      "size",
      "created_at",
      "active",
      "numericality",
      "build_type",
      "phone_number",
      "agree_to_terms"
    ]
  end

  # Sub resources allowed to be included in the response
  def includes
    [ :photos, :landlord, :english_name, :document ]
  end

  # Sub resourced allowed to be set during create / update / delete if a user is
  # allowed to ....
  # only add to and from the relation, can also create or update the subresource
  def nested
    [ :photos, :accounts, :non_include_photo ]
  end

end
