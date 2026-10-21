module PhotoACL

  def attributes
    [
      :format
    ]
  end
  
  # Sub resources allowed to be included in the response
  def includes
    [ :account ]
  end

  def wheres
    [ :id, :account_id, :properties ]
  end

  def nested
    [ :account, :camera ]
  end

end
