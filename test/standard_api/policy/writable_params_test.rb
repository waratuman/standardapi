require 'standard_api/test_helper'

# Controller#filter_model_params keeps a writable param only when it's what
# the Policy says it takes (Policy#writable_attributes), as strong parameters
# keep only a permitted scalar for a scalar, and so on
class PolicyWritableParamsTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  # What Controller#filter_model_params keeps of +params+ for +record+, a
  # create of a Camera by default, with CamerasController::Policy and
  # +declarations+
  def filtered(declarations, params, record = Camera.new)
    with_camera_policy(declarations) do
      CamerasController.new.send(:filter_model_params, record, ActionController::Parameters.new(params)).to_h
    end
  end

  # What it keeps of +params+ for +record+, a create of a Property by
  # default, with a Policy that makes name and aliases, an array column on
  # Postgres, writable
  def filtered_property(params, record = Property.new)
    with_model_policy(Property, Class.new(StandardAPI::Policy) { attributes :name, :aliases, writable: true }) do
      PropertiesController.new.send(:filter_model_params, record, ActionController::Parameters.new(params)).to_h
    end
  end

  def uploaded_file
    Rack::Test::UploadedFile.new(File.join(Rails.root, 'test/fixtures/photo.png'), 'image/png')
  end

  test 'a scalar column takes what strong parameters permit as a scalar, null included' do
    upload = ActionDispatch::Http::UploadedFile.new(tempfile: Tempfile.new, filename: 'photo.png')
    ['Leica', :leica, 1, 1.5, BigDecimal('2'), true, false, nil, Date.today, Time.now, uploaded_file, upload, StringIO.new('x')].each do |value|
      assert_equal({ 'make' => value }, filtered(proc { attribute :make, writable: true }, make: value), value.inspect)
    end
  end

  test 'a scalar column drops a hash or an array' do
    [{ 'a' => 1 }, {}, ['Leica'], [], [{ 'a' => 1 }]].each do |value|
      assert_equal({}, filtered(proc { attribute :make, writable: true }, make: value), value.inspect)
    end
  end

  test 'an attribute without a column takes a scalar, ie. an uploaded file' do
    file = uploaded_file
    params = DocumentsController.new.send(:filter_model_params, Document.new, ActionController::Parameters.new(type: 'Pdf', file: file))
    assert_equal({ 'type' => 'Pdf', 'file' => file }, params.to_h)

    params = DocumentsController.new.send(:filter_model_params, Document.new, ActionController::Parameters.new(file: { 'a' => 1 }))
    assert_equal({}, params.to_h)
  end

  test 'a scalar column takes a multiparameter attribute' do
    params = { 'photo_cached_at(1i)' => '2024', 'photo_cached_at(2i)' => '5', 'photo_cached_at(3i)' => '6', 'photo_cached_atx(1i)' => '1' }
    assert_equal params.except('photo_cached_atx(1i)'), filtered(proc { attribute :photo_cached_at, writable: true }, params)
  end

  test 'an array column takes an array of scalars, or null' do
    skip 'array columns are a Postgres-only feature' if !postgres?

    [['a', 'b'], [], nil].each do |value|
      assert_equal({ 'aliases' => value }, filtered_property(aliases: value), value.inspect)
    end
  end

  test 'an array column drops a hash, a scalar, or an array of what is not a scalar' do
    skip 'array columns are a Postgres-only feature' if !postgres?

    [{ 'a' => 'b' }, {}, 'a', [{ 'a' => 'b' }], [['a']], ['a', { 'b' => 'c' }]].each do |value|
      assert_equal({}, filtered_property(aliases: value), value.inspect)
    end
  end

  test 'a json column takes any JSON value, and drops what is not one' do
    value = { 'a' => [1, nil, { 'b' => ['c', true] }], 'd' => {} }
    assert_equal({ 'metadata' => value }, filtered(proc { attribute :metadata, writable: true }, metadata: value))
    assert_equal({ 'metadata' => nil }, filtered(proc { attribute :metadata, writable: true }, metadata: nil))
    assert_equal({}, filtered(proc { attribute :metadata, writable: true }, metadata: Object.new))
    assert_equal({}, filtered(proc { attribute :metadata, writable: true }, metadata: [Object.new]))
  end

  test 'a permit applies its strong parameters shape' do
    assert_equal({ 'metadata' => { 'a' => 1 } }, filtered(proc { attribute :metadata, writable: [:a] }, metadata: { a: 1, b: 2 }))
    assert_equal({ 'metadata' => [{ 'a' => 1 }] }, filtered(proc { attribute :metadata, writable: [:a] }, metadata: [{ a: 1, b: 2 }]))
    assert_equal({ 'make' => ['a', 'b'] }, filtered(proc { writable :make, permit: [] }, make: ['a', 'b']))
    assert_equal({}, filtered(proc { writable :make, permit: [] }, make: 'a'))
    assert_equal({ 'metadata' => { 'a' => { 'b' => 1 } } }, filtered(proc { writable :metadata, permit: {} }, metadata: { a: { b: 1 } }))
    # As strong parameters do, a permit drops null
    assert_equal({}, filtered(proc { attribute :metadata, writable: [:a] }, metadata: nil))
  end

  test 'on: :create or :update keeps it only on one, a new record being a create' do
    declarations = proc do
      attribute :make, writable: { on: :update }
      attribute :metadata, writable: { on: :create }
    end
    params = { make: 'Leica', metadata: [1] }

    assert_equal({ 'metadata' => [1] }, filtered(declarations, params))
    assert_equal({ 'make' => 'Leica' }, filtered(declarations, params, create(:camera)))
  end

  test 'a nested record takes its id' do
    assert_equal({ 'id' => 1 }, with_camera_policy(proc {}) {
      CamerasController.new.send(:filter_model_params, Camera.new, ActionController::Parameters.new(id: 1), allow_id: true).to_h
    })
    assert_equal({}, with_camera_policy(proc {}) {
      CamerasController.new.send(:filter_model_params, Camera.new, ActionController::Parameters.new(id: { 'a' => 1 }), allow_id: true).to_h
    })
  end

  test 'what is dropped is reported as strong parameters report an unpermitted parameter' do
    reported = []
    subscriber = ActiveSupport::Notifications.subscribe('unpermitted_parameters.action_controller') { |*, payload| reported << payload[:keys] }
    ActionController::Parameters.stubs(:action_on_unpermitted_parameters).returns(:log)

    # account and account_id are written through the association, so aren't
    # reported
    params = { format: { 'a' => 1 }, account_id: 1, account: nil, bogus: 1, controller: 'photos' }
    PhotosController.new.send(:filter_model_params, Photo.new, ActionController::Parameters.new(params))
    assert_equal [['format', 'bogus']], reported

    reported.clear
    PhotosController.new.send(:filter_model_params, Photo.new, ActionController::Parameters.new(format: 'png'))
    assert_equal [], reported

    ActionController::Parameters.stubs(:action_on_unpermitted_parameters).returns(:raise)
    assert_raises(ActionController::UnpermittedParameters) do
      PhotosController.new.send(:filter_model_params, Photo.new, ActionController::Parameters.new(bogus: 1))
    end
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test 'POST create drops a hash sent to a string column, and PATCH update an array' do
    with_camera_policy(proc { attribute :make, writable: true }) do
      camera = create(:camera, make: 'Leica')
      patch camera_path(camera, format: 'json'), params: { camera: { make: ['Canon'] } }, as: :json
      assert_response :ok
      assert_equal 'Leica', camera.reload.make

      assert_no_difference 'Camera.count' do
        post cameras_path(format: 'json'), params: { camera: { make: { 'a' => 'Canon' } } }, as: :json
      end
    end
  end

  test 'PATCH update sets a scalar and an array column to null' do
    skip 'array columns are a Postgres-only feature' if !postgres?

    property = create(:property, aliases: ['a'])
    patch property_path(property, format: 'json'), params: { property: { aliases: nil, description: nil } }, as: :json
    assert_response :ok
    assert_equal [nil, nil], [property.reload.aliases, property.description]
  end

end
