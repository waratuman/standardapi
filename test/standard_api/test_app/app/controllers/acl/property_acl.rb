module PropertyACL

  # Sub resources allowed to be included in the response
  # Sub resourced allowed to be set during create / update / delete if a user is
  # allowed to ....
  # only add to and from the relation, can also create or update the subresource
  def nested
    [ :photos, :accounts ]
  end

end
