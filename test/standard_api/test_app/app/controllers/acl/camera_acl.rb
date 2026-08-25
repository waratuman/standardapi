module CameraACL

  def attributes
    [ :make, :hidden, :retired, :photo_id ]
  end

  # Sub resources allowed to be included in the response
  def includes
    [ :photo ]
  end

  # Attributes to exclude from the response, evaluated per-record. Dedicated
  # to exercising ACL excludes in isolation from Property/Account, which are
  # exercised by the much larger StandardAPI::TestCase generic suite.
  def excludes(record)
    result = {}
    result[:make] = true if record.hidden?
    result[:photo] = record.retired? ? true : ([:format] if record.hidden?)
    result.compact
  end

end
