require 'standard_api/test_helper'

# A writable json column takes any JSON value, as schema/write.json describes
# it: an object, an array, a scalar or null, nested to any depth
class PolicyWritableJSONTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  VALUES = {
    'an object' => { 'a' => 1, 'b' => 'two' },
    # Rails' deep munge drops a null from an array in the params, before
    # StandardAPI sees them
    'an array of scalars' => [1, 'two', 3.5, true],
    'an array of objects' => [{ 'a' => 1 }, { 'b' => [2, 3] }],
    'a nested structure' => { 'a' => [{ 'b' => [[1, 2], [{ 'c' => nil }]] }], 'd' => { 'e' => { 'f' => false } } },
    'an empty object' => {},
    'an empty array' => [],
    'a string' => 'x',
    'a number' => 1,
    'a boolean' => false,
    'null' => nil
  }.freeze

  def writable_json(policy, record = nil)
    policy.new(CamerasController.new, Camera).permitted_json_attributes(record)
  end

  test 'writable json attributes are the json columns writable on that action, without a permit' do
    policy = empty_policy_class do
      attributes :make, :metadata, writable: true
    end
    assert_equal %w[metadata], writable_json(policy)

    assert_equal [], writable_json(empty_policy_class { attribute :metadata })
    assert_equal [], writable_json(empty_policy_class { attribute :metadata, writable: { permit: {} } })
    assert_equal [], writable_json(empty_policy_class { attribute :metadata, writable: [:a] })

    policy = empty_policy_class { attribute :metadata, writable: { on: :update } }
    assert_equal [], writable_json(policy)
    assert_equal %w[metadata], writable_json(policy, create(:camera))
  end

  test 'Policy::Record#writable_json is empty without a Policy' do
    with_model_policy(Camera, nil) do
      assert_equal [], ApplicationController.new.record_policy(Camera).writable_json
    end
  end

  VALUES.each do |description, value|
    test "POST create and PATCH update save #{description} to a writable json column as sent" do
      with_camera_policy(proc { attribute :metadata, writable: true }) do
        post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: value } }, as: :json
        assert_response :created
        camera = Camera.last
        assert_equal value, camera.reload.metadata

        camera.update!(metadata: 'before')
        patch camera_path(camera, format: 'json'), params: { camera: { metadata: value } }, as: :json
        assert_response :ok
        assert_equal value, camera.reload.metadata
      end
    end
  end

  test "a json column that isn't writable isn't written" do
    with_camera_policy(proc { attribute :metadata }) do
      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: [{ 'a' => 1 }] } }, as: :json
      assert_response :created
      assert_nil Camera.last.metadata
    end
  end

  test 'a json column writable only on create is not written on update' do
    with_camera_policy(proc { attribute :metadata, writable: { on: :create } }) do
      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: [1, 2] } }, as: :json
      assert_response :created
      camera = Camera.last
      assert_equal [1, 2], camera.reload.metadata

      patch camera_path(camera, format: 'json'), params: { camera: { metadata: [3] } }, as: :json
      assert_response :ok
      assert_equal [1, 2], camera.reload.metadata
    end
  end

  test 'a permit on a json column takes the place of any JSON value' do
    with_camera_policy(proc { attribute :metadata, writable: [:a] }) do
      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: { 'a' => 1, 'b' => 2 } } }, as: :json
      assert_response :created
      assert_equal({ 'a' => 1 }, Camera.last.reload.metadata)

      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: [{ 'a' => 1, 'b' => 2 }] } }, as: :json
      assert_response :created
      assert_equal [{ 'a' => 1 }], Camera.last.reload.metadata

      post cameras_path(format: 'json'), params: { camera: { make: 'Leica', metadata: 'x' } }, as: :json
      assert_response :created
      assert_nil Camera.last.reload.metadata
    end
  end

  test 'a nested record writes any JSON value to a json column its Policy makes writable' do
    camera_policy = Class.new(StandardAPI::Policy) { attributes :make, :metadata, writable: true }
    photo_policy = Class.new(PhotoPolicy) { writable :camera, policy: camera_policy }
    value = [{ 'a' => [1, { 'b' => nil }] }, [2, 3], 'x']

    with_model_policy(Photo, photo_policy) do
      post photos_path, params: { photo: { camera: { make: 'Sony', metadata: value } } }, as: :json
      assert_response :created
      camera = Photo.last.camera
      assert_equal value, camera.reload.metadata

      put photo_path(Photo.last), params: { photo: { camera: { id: camera.id, metadata: [{ 'c' => 4 }] } } }, as: :json
      assert_response :ok
      assert_equal [{ 'c' => 4 }], camera.reload.metadata
    end
  end

  test "a nested record doesn't write a json column its Policy doesn't make writable" do
    camera_policy = Class.new(StandardAPI::Policy) { attribute :make, writable: true; attribute :metadata }
    photo_policy = Class.new(PhotoPolicy) { writable :camera, policy: camera_policy }

    with_model_policy(Photo, photo_policy) do
      post photos_path, params: { photo: { camera: { make: 'Sony', metadata: [{ 'a' => 1 }] } } }, as: :json
      assert_response :created
      assert_nil Photo.last.camera.reload.metadata
    end
  end

end
