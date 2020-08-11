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
    Account.any_instance.expects(:property_cached_at).returns(t1)
    Account.any_instance.expects(:subject_cached_at).returns(t1)
    get account_path(account, include: { property: true, subject: true }, format: 'json')
    json = JSON(response.body)
    assert json.has_key?('property')
    assert json.has_key?('subject')
  end

end
