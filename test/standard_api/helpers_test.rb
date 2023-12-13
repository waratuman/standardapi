require 'standard_api/test_helper'

class HelpersTest < ActionView::TestCase
  include StandardAPI::Helpers

  test "::cached_at_columns_for_includes(includes)" do
    assert_equal(
      ['photos_cached_at'],
      cached_at_columns_for_includes({photos: {}})
    )

    assert_equal(
      ['photos_cached_at', 'photos_account_cached_at'],
      cached_at_columns_for_includes({photos: {account: {}}})
    )

    assert_equal(
      ['photos_cached_at', 'photos_account_cached_at', 'photos_properties_cached_at'],
      cached_at_columns_for_includes({photos: {account: {}, properties: {}}})
    )

    assert_equal(
      ['photos_cached_at', 'photos_account_cached_at', 'photos_properties_cached_at', 'photos_properties_landlord_cached_at'],
      cached_at_columns_for_includes({photos: {account: {}, properties: {landlord: {}}}})
    )
  end

  test "::can_cache?" do
    Account.expects(:column_names).returns(['id'])
    assert !can_cache?(Account, {})

    Account.expects(:column_names).returns(['id', 'cached_at'])
    assert can_cache?(Account, {})

    Account.expects(:column_names).returns(['id', 'cached_at'])
    assert !can_cache?(Account, {photos: {}})

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at'])
    assert can_cache?(Account, {photos: {}})

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at'])
    assert !can_cache?(Account, {photos: {account: {}}})

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_account_cached_at'])
    assert can_cache?(Account, {photos: {account: {}}})
  end

  test '::can_cache_relation? with non-persisted record' do
    account = build(:account)
    assert !can_cache_relation?(account, :photos, {})
    assert !can_cache_relation?(account, :photos, {})
    assert !can_cache_relation?(account, :photos, {account: {}})
    assert !can_cache_relation?(account, :photos, {account: {}})
  end

  test '::can_cache_relation? with persisted record' do
    account = create(:account)

    Account.expects(:column_names).returns(['id', 'cached_at'])
    assert !can_cache_relation?(account, :photos, {})

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at'])
    assert can_cache_relation?(account, :photos, {})

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at'])
    assert !can_cache_relation?(account, :photos, {account: {}})

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_account_cached_at'])
    assert can_cache_relation?(account, :photos, {account: {}})
  end

  test '::association_cache_key(record, relation, subincludes)' do
    account = create(:account)
    photo = create(:photo, account: account)
    t1 = Time.now
    t2 = 1.day.from_now
    t3 = 2.days.from_now

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_property_cached_at'])
    account.expects(:photos_cached_at).returns(t1)

    assert_equal(
      "accounts/#{account.id}/photos-#{t1.utc.to_s(ActiveRecord::Base.cache_timestamp_format)}",
      association_cache_key(account, :photos, {})
    )

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_property_cached_at'])
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    assert_equal(
      "accounts/#{account.id}/photos-2ea683a694a33359514c41435f8f0646-#{t2.utc.to_s(ActiveRecord::Base.cache_timestamp_format)}",
      association_cache_key(account, :photos, {property: {}})
    )

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_property_cached_at'])
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    assert_equal(
      "accounts/#{account.id}/photos-65b1019b2d108a0808bd98579e1f2793-#{t2.utc.to_s(ActiveRecord::Base.cache_timestamp_format)}",
      association_cache_key(account, :photos, { "property" =>  { "sort" => { "x" => "desc" }}})
    )

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_property_cached_at', 'photos_agents_cached_at'])
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    account.expects(:photos_agents_cached_at).returns(t3)
    assert_equal(
      "accounts/#{account.id}/photos-abbee2d4535400c162c8dbf14bbef6d5-#{t3.utc.to_s(ActiveRecord::Base.cache_timestamp_format)}",
      association_cache_key(account, :photos, {property: {}, agents: {}})
    )

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_property_cached_at', 'photos_property_agents_cached_at'])
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    account.expects(:photos_property_agents_cached_at).returns(t3)
    assert_equal(
      "accounts/#{account.id}/photos-0962ae73347c5c605d329eaa25e2be49-#{t3.utc.to_s(ActiveRecord::Base.cache_timestamp_format)}",
      association_cache_key(account, :photos, {property: {agents: {}}})
    )

    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_property_cached_at', 'photos_agents_cached_at', 'photos_property_addresses_cached_at'])
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    account.expects(:photos_agents_cached_at).returns(t2)
    account.expects(:photos_property_addresses_cached_at).returns(t3)
    assert_equal(
      "accounts/#{account.id}/photos-00ea6afe3ff68037f8b4dcdb275e2a24-#{t3.utc.to_s(ActiveRecord::Base.cache_timestamp_format)}",
      association_cache_key(account, :photos, {property: {addresses: {}}, agents: {}})
    )

    # Belongs to
    Photo.expects(:column_names).returns(['id', 'cached_at', 'account_cached_at'])
    photo.expects(:account_cached_at).returns(t1)
    assert_equal(
      "accounts/#{account.id}-#{t1.utc.to_s(ActiveRecord::Base.cache_timestamp_format)}",
      association_cache_key(photo, :account, {})
    )

    Photo.expects(:column_names).returns(['id', 'cached_at', 'account_cached_at', 'account_photos_cached_at'])
    photo.expects(:account_cached_at).returns(t1)
    photo.expects(:account_photos_cached_at).returns(t2)
    assert_equal(
      "accounts/#{account.id}/07437ce3863467f4cd715ae1ef930f08-#{t2.utc.to_s(ActiveRecord::Base.cache_timestamp_format)}",
      association_cache_key(photo, :account, {photos: {}})
    )
  end

  test '::json_column_type(sql_type)' do
    assert_equal 'string', json_column_type('character varying')
    assert_equal 'string', json_column_type('character varying(2)')
    assert_equal 'string', json_column_type('character varying(255)')
    assert_equal 'datetime', json_column_type('timestamp without time zone')
    assert_equal 'datetime', json_column_type('timestamp(6) without time zone')
    assert_equal 'datetime', json_column_type('time without time zone')
    assert_equal 'string', json_column_type('text')
    assert_equal 'hash', json_column_type('json')
    assert_equal 'hash', json_column_type('jsonb')
    assert_equal 'integer', json_column_type('bigint')
    assert_equal 'integer', json_column_type('integer')
    assert_equal 'string', json_column_type('inet')
    assert_equal 'hash', json_column_type('hstore')
    assert_equal 'datetime', json_column_type('date')
    assert_equal 'decimal', json_column_type('numeric')
    assert_equal 'decimal', json_column_type('numeric(12)')
    assert_equal 'decimal', json_column_type('numeric(12,2)')
    assert_equal 'decimal', json_column_type('double precision')
    assert_equal 'string', json_column_type('ltree')
    assert_equal 'boolean', json_column_type('boolean')
    assert_equal 'ewkb', json_column_type('geometry')
    assert_equal 'string', json_column_type('uuid')
  end

end
