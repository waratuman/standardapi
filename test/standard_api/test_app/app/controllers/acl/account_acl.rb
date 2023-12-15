module AccountACL

  def attributes
    [ "property_id", "name" ]
  end

  def orders
    [ "id" ]
  end

  def includes
    [ "orders", "photos", "subject", "property" ]
  end

end
