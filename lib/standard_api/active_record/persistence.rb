require "active_record/persistence"

# If an association can't be saved, default to returning. By default, Rails does this
# for just the record, but not any of it's assocations.
module ActiveRecord::Persistence

  def save(**options, &block)
    create_or_update(**options, &block)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
    false
  end

  def update(attributes)
    with_transaction_returning_status do
      assign_attributes(attributes)
      save
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
    false
  end

end
