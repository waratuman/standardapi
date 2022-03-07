module PhotoACL

  def attributes
    [
      :format
    ]
  end
  
  def nested
    [ :account, :camera, :properties ]
  end
  
  def includes
    [ :properties ]
  end

end
