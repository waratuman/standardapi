module PhotoACL

  def attributes(record = nil)
    [
      :format
    ]
  end

  def wheres
    [ :id, :account_id, :properties ]
  end

  def nested
    [ :account, :camera ]
  end

end
