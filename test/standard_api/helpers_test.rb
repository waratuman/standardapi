require 'test_helper'

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
  
  test '::can_cache_relation?' do
    Account.expects(:column_names).returns(['id', 'cached_at'])
    assert !can_cache_relation?(Account, :photos, {})
    
    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at'])
    assert can_cache_relation?(Account, :photos, {})
    
    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at'])
    assert !can_cache_relation?(Account, :photos, {account: {}})
    
    Account.expects(:column_names).returns(['id', 'cached_at', 'photos_cached_at', 'photos_account_cached_at'])
    assert can_cache_relation?(Account, :photos, {account: {}})
  end
  
  test '::association_cache_key(record, relation, subincludes)' do
    account = create(:account)
    t1 = Time.now
    t2 = 1.day.from_now
    t3 = 2.days.from_now

    account.expects(:photos_cached_at).returns(t1)
    
    assert_equal(
      "accounts/#{account.id}/photos-#{t1.utc.to_s(:nsec)}",
      association_cache_key(account, :photos, {})
    )
    
    
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    assert_equal(
      "accounts/#{account.id}/photos-2ea683a694a33359514c41435f8f0646-#{t2.utc.to_s(:nsec)}",
      association_cache_key(account, :photos, {property: {}})
    )
    
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    assert_equal(
      "accounts/#{account.id}/photos-779c17ef027655fd8c06c3083d2df64b-#{t2.utc.to_s(:nsec)}",
      association_cache_key(account, :photos, {property: {order: {x: :desc}}})
    )
    
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    account.expects(:photos_agents_cached_at).returns(t3)
    assert_equal(
      "accounts/#{account.id}/photos-abbee2d4535400c162c8dbf14bbef6d5-#{t3.utc.to_s(:nsec)}",
      association_cache_key(account, :photos, {property: {}, agents: {}})
    )

    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    account.expects(:photos_property_agents_cached_at).returns(t3)
    assert_equal(
      "accounts/#{account.id}/photos-0962ae73347c5c605d329eaa25e2be49-#{t3.utc.to_s(:nsec)}",
      association_cache_key(account, :photos, {property: {agents: {}}})
    )
        
    account.expects(:photos_cached_at).returns(t1)
    account.expects(:photos_property_cached_at).returns(t2)
    account.expects(:photos_agents_cached_at).returns(t2)
    account.expects(:photos_property_addresses_cached_at).returns(t3)
    assert_equal(
      "accounts/#{account.id}/photos-00ea6afe3ff68037f8b4dcdb275e2a24-#{t3.utc.to_s(:nsec)}",
      association_cache_key(account, :photos, {property: {addresses: {}}, agents: {}})
    )
    
    # Belongs to
    photo = create(:photo, account: account)
    photo.expects(:account_cached_at).returns(t1)
    assert_equal(
      "accounts/#{account.id}-#{t1.utc.to_s(:nsec)}",
      association_cache_key(photo, :account, {})
    )
    
    photo = create(:photo, account: account)
    photo.expects(:account_cached_at).returns(t1)
    photo.expects(:account_photos_cached_at).returns(t2)
    assert_equal(
      "accounts/#{account.id}/07437ce3863467f4cd715ae1ef930f08-#{t2.utc.to_s(:nsec)}",
      association_cache_key(photo, :account, {photos: {}})
    )
    
  end
  
end