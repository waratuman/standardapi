module CameraACL

  def attributes
    [ :make, :hidden, :retired, :photo_id ]
  end

  # Sub resources allowed to be included in the response
  def includes
    { photo: [ :account ] }
  end

  # Attributes to exclude from the response, evaluated per-record. Dedicated
  # to exercising ACL excludes in isolation from Property/Account, which are
  # exercised by the much larger StandardAPI::TestCase generic suite.
  def excludes(record)
    result = {}
    # `false` and `nil` exclude nothing, so predicates can be assigned directly.
    result[:make] = record.hidden?
    # `photos/_photo` is a custom partial, so this whole sub-tree is only
    # honoured because that partial resolves and applies it. The `account`
    # branch goes one level deeper, into application/_record.
    result[:photo] = record.retired? ? true : ({ format: true, created_at: true, account: [:email] } if record.hidden?)

    # Stands in for an ACL that varies by *requester* (current_user, role,
    # token) rather than by record. That is the case fragment caching has to
    # defend against, since the cache keys are built from record timestamps
    # alone and cannot tell two requesters apart.
    result[:photo] = [:format] if result[:photo].nil? && request.headers['X-Hide-Photo-Format'] == '1'

    result
  end

end
