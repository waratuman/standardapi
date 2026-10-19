module AccountACL

  def attributes
    [ "property_id", "name" ]
  end

  def orders
    [ "id", "property" ]
  end

  def includes
    {
      photos: true,
      subject: [ 'landlord' ],
      property: true
    }
  end

end
