module PhotoACL

  def attributes(record = nil)
    [
      :format
    ]
  end

  def nested
    [ :account, :camera ]
  end

end
