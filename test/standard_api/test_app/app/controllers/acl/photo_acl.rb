module PhotoACL

  def attributes
    [
      :format
    ]
  end
  
  def nested
    { account: true, camera: true }
  end

end
