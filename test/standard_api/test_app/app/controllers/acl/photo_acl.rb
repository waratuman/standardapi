module PhotoACL

  def attributes
    [
      :format
    ]
  end
  
  def nested
    [ :account, :camera ]
  end

end
