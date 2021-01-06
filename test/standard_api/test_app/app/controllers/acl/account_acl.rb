module AccountACL

  def attributes
    [ "property_id", "name" ]
  end

  def orders
    [ "id" ]
  end

  def includes
    [ "photos", "subject", "property" ]
  end

end
