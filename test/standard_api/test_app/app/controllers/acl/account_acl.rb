module AccountACL

  def attributes
    [ "property_id", "name" ]
  end

  def sorts
    [ "id" ]
  end

  def includes
    [ "photos", "subject", "property" ]
  end

end
