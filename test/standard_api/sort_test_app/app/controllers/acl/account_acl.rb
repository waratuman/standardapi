module AccountACL

  def attributes
    [ "name" ]
  end

  def orders
    [ "id", "name" ]
  end

  def includes
    [ "orders" ]
  end

end
