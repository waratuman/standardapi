module OrderACL

  # Attributes allowed to be updated
  def attributes
    [ :name,
      :price,
      :account_id
    ]
  end

  # Orderings allowed
  def orders
    [ "id", "account_id", "price" ]
  end

  # Sub resources allowed to be included in the response
  def includes
    [ :account ]
  end

end
