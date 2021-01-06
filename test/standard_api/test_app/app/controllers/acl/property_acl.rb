module PropertyACL

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

  def orders
    ["id", "name", "aliases", "description", "constructed", "size", "created_at", "active"]
  end

  def includes
    [ :photos, :landlord, :english_name, :document ]
  end

  def nested
    [ :photos ]
  end

end
