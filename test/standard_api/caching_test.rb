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

  # A record of an STI subclass renders with the subclass's Policy, not the
  # one of the class the association declares, so it's the subclass's Policy
  # that decides whether the fragment can be cached.

  test 'an STI subclass rendered with a Policy that varies is not cached for another requester' do
    camera = create(:camera)
    Flash.create!(camera: camera, name: 'Speedlite', serial: 'SN-1')

    columns = Camera.column_names + ['accessory_cached_at']
    Camera.stubs(:column_names).returns(columns)
    Camera.any_instance.stubs(:accessory_cached_at).returns(1.day.from_now)

    with_camera_policy(-> { association :accessory }) do
      # An admin warms the fragment.
      get camera_path(camera, include: :accessory, format: :json), headers: { 'X-Admin' => '1' }
      assert_equal 'SN-1', JSON(response.body)['accessory']['serial']

      # Anyone else must not receive what the admin was rendered.
      get camera_path(camera, include: :accessory, format: :json)
      assert_equal 'Speedlite', JSON(response.body)['accessory']['name']
      assert !JSON(response.body)['accessory'].key?('serial'),
        'an attribute leaked from a fragment cached for a different requester'
    end
  end

  test 'a model varies by requester when the Policy of one of its STI subclasses does' do
    controller = CamerasController.new

    assert !AccessoryPolicy.varies_by_requester?
    assert FlashPolicy.varies_by_requester?
    assert controller.send(:policy_varies?, Flash)
    assert controller.send(:policy_varies?, Accessory)
    assert controller.send(:policy_varies?, Camera, { 'accessory' => {} })

    # Photo has no subclasses, and Document isn't STI
    assert !controller.send(:policy_varies?, Photo)
    assert !controller.send(:policy_varies?, Document)
  end

  test 'STI subclasses are loaded before their Policies are checked, when the app is not eager loaded' do
    Rails.application.config.stubs(:eager_load).returns(false)
    Rails.application.expects(:eager_load!).once

    controller = CamerasController.new
    assert controller.send(:policy_varies?, Accessory)
    # Not STI, so there are no subclasses to load
    assert !controller.send(:policy_varies?, Photo)
  end

end
