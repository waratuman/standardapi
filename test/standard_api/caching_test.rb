require 'test_helper'

class AccountsControllerTest < ActionController::TestCase

  test 'include with cache' do
    account = create(:account, photos: [])
    photo = create(:photo, account_id: account.id)

    t1 = 1.day.from_now
    t2 = 2.days.from_now
    
    columns = Account.column_names + ['photos_account_cached_at', 'photos_cached_at']
    Account.stubs(:column_names).returns(columns)
    
    # Cache Miss
    Account.any_instance.stubs(:photos_cached_at).returns(t1)
    get :show, id: account.id, include: :photos, format: :json
    assert_equal [photo.id], JSON(response.body)['photos'].map{|x| x['id']}
    
    # Cache Hit
    Account.any_instance.stubs(:photos).returns([])
    Account.any_instance.stubs(:photos_cached_at).returns(t1)
    get :show, id: account.id, include: :photos, format: :json
    assert_equal [photo.id], JSON(response.body)['photos'].map{|x| x['id']}
    
    # Cache Miss, photos_cached_at updated
    Account.any_instance.stubs(:photos).returns(Photo.where('false = true'))
    Account.any_instance.stubs(:photos_cached_at).returns(t2)
    get :show, id: account.id, include: :photos, format: :json
    assert_equal [], JSON(response.body)['photos'].map{|x| x['id']}
  end

end
