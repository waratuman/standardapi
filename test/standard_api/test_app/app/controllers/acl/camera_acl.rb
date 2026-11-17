module CameraACL

  def attributes(record = nil)
    [ :make, :hidden, :retired, :photo_id ]
  end

  # Sub resources allowed to be included in the response
end
