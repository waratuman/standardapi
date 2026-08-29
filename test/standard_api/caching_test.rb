require 'standard_api/test_helper'

class AccountsControllerTest < ActionDispatch::IntegrationTest

  test 'include with cache' do
    account = create(:account, photos: [])
    photo = create(:photo, account_id: account.id)

    t1 = 1.day.from_now
    t2 = 2.days.from_now

    columns = Account.column_names + ['photos_account_cached_at', 'photos_cached_at']
    Account.stubs(:column_names).returns(columns)

    # Cache Miss
    Account.any_instance.stubs(:photos_cached_at).returns(t1)
    get account_path(account, include: :photos, format: :json)
    assert_equal [photo.id], JSON(response.body)['photos'].map{|x| x['id']}

    # Cache Hit
    Account.any_instance.stubs(:photos).returns([])
    Account.any_instance.stubs(:photos_cached_at).returns(t1)
    get account_path(account, include: :photos, format: :json)
    assert_equal [photo.id], JSON(response.body)['photos'].map{|x| x['id']}

    # Cache Miss, photos_cached_at updated
    Account.any_instance.stubs(:photos).returns(Photo.where('false = true'))
    Account.any_instance.stubs(:photos_cached_at).returns(t2)
    get account_path(account, include: :photos, format: :json)
    assert_equal [], JSON(response.body)['photos'].map{|x| x['id']}

    # Two associations that reference the same model
    property = create(:property)
    account = create(:account, property: property, subject: property)
    Account.any_instance.expects(:property_cached_at).twice.returns(t1)
    Account.any_instance.expects(:subject_cached_at).twice.returns(t1)
    get account_path(account, include: { property: true, subject: true }, format: 'json')
    json = JSON(response.body)
    assert json.has_key?('property')
    assert json.has_key?('subject')
  end

  # Included collections are filtered through #mask, but the cache key is built
  # from record timestamps only, so a masked association must not be cached.

  test 'masked rows are not served from a fragment cached for another requester' do
    account = create(:account, photos: [])
    photo = create(:photo, account_id: account.id)

    columns = Account.column_names + ['photos_cached_at']
    Account.stubs(:column_names).returns(columns)
    Account.any_instance.stubs(:photos_cached_at).returns(1.day.from_now)

    # An unmasked requester warms the fragment.
    get account_path(account, include: :photos, format: :json)
    assert_equal [photo.id], JSON(response.body)['photos'].map { |x| x['id'] }

    # A requester the mask hides those rows from must not receive them.
    get account_path(account, include: :photos, format: :json),
      headers: { 'X-Hide-Photos' => '1' }
    assert_equal [], JSON(response.body)['photos'].map { |x| x['id'] },
      'masked rows leaked from a fragment cached for a different requester'
  end

  test 'a masked requester does not poison the fragment cache for others' do
    account = create(:account, photos: [])
    photo = create(:photo, account_id: account.id)

    columns = Account.column_names + ['photos_cached_at']
    Account.stubs(:column_names).returns(columns)
    Account.any_instance.stubs(:photos_cached_at).returns(2.days.from_now)

    # The masked requester renders first.
    get account_path(account, include: :photos, format: :json),
      headers: { 'X-Hide-Photos' => '1' }
    assert_equal [], JSON(response.body)['photos'].map { |x| x['id'] }

    # An unmasked requester must still see the rows.
    get account_path(account, include: :photos, format: :json)
    assert_equal [photo.id], JSON(response.body)['photos'].map { |x| x['id'] },
      'permitted rows were hidden by a fragment cached for a masked requester'
  end

end

class CacheableAccountsControllerTest < ActionDispatch::IntegrationTest

  test 'eager-loaded collection cache expires when another cache timestamp changes' do
    timestamp = Time.utc(2025, 1, 2)
    CacheableAccount.fixed_cache_timestamp = timestamp
    account = CacheableAccount.create!

    get cacheable_accounts_path(format: :json), params: { include: :photos, limit: 100 }
    records = JSON(response.body)
    records = records['cache_collection!'] if records.is_a?(Hash)
    assert_nil records.first['property_cached_at']

    # The changed value equals the existing maximum cache timestamp. A key
    # based only on the maximum therefore serves the stale fragment above.
    account.update!(property_cached_at: timestamp)

    get cacheable_accounts_path(format: :json), params: { include: :photos, limit: 100 }
    records = JSON(response.body)
    records = records['cache_collection!'] if records.is_a?(Hash)
    assert_equal account.property_cached_at.as_json,
      records.first['property_cached_at']
  ensure
    CacheableAccount.fixed_cache_timestamp = nil
  end

end
