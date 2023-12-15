module AccountACL

  def attributes
    [ "name" ]
  end

  def orders
    [ "id", "name" ]
  end

  def includes
    [ "order", "orders" ]
  end

end
