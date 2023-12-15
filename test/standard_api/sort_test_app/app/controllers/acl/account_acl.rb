module AccountACL

  def attributes
    [ "name" ]
  end

  def orders
    [ "id", "name" ]
  end

  def includes
    {
      order: true,
      orders: {
        account: { order: true }
      }
    }
  end

end
