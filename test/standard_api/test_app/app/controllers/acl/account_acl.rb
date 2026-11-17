module AccountACL

  def attributes(record = nil)
    [ "property_id", "name" ]
  end

  def wheres
    [ "id" ]
  end

end
