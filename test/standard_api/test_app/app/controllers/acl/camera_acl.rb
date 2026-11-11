module CameraACL

  def attributes(record = nil)
    [ :make, :hidden, :retired, :photo_id ]
  end

  # Filters allowed in the `where` param
  def wheres
    [ :id, :make, { photo_id: [:eq, :in] }, :photo ]
  end

  # Sub resources allowed to be included in the response
  def includes
    [ :photo, :specs ]
  end

end
