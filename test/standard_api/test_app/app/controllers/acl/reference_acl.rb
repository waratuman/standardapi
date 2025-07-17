module ReferenceACL

  def nested
    [ :subject ]
  end

  def includes
    { subject: [ :landlord, :photos ] }
  end

end
