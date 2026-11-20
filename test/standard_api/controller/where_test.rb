require 'standard_api/test_helper'

# Wheres are checked against CamerasController::Policy, which makes id and
# make filterable with any operator, photo_id with eq and in, and the photo
# association, through which PhotoPolicy decides.
class ControllerWhereTest < ActionDispatch::IntegrationTest

  def ids(params)
    get cameras_path(format: :json), params: { limit: 100 }.merge(params)
    assert_response :ok
    JSON(response.body).map { |x| x['id'] }.sort
  end

  def assert_unpermitted(params, message)
    get cameras_path(format: :json), params: { limit: 100 }.merge(params)
    assert_response :bad_request
    assert_equal message, response.body
  end

  test "a column permits any operator" do
    leica = create(:camera, make: 'Leica')
    create(:camera, make: 'Sony')

    assert_equal [leica.id], ids(where: { make: 'Leica' })
    assert_equal [leica.id], ids(where: { make: { like: 'Lei%' } })
    assert_equal [leica.id], ids(where: { make: { not_in: ['Sony'] } })
  end

  test "a column permits only the operators listed" do
    photo = create(:photo)
    camera = create(:camera, photo: photo)
    create(:camera)

    assert_equal [camera.id], ids(where: { photo_id: photo.id })
    assert_equal [camera.id], ids(where: { photo_id: [photo.id] })
    assert_equal [camera.id], ids(where: { photo_id: { equal_to: photo.id } })

    assert_unpermitted({ where: { photo_id: { gt: 0 } } }, 'found unpermitted parameter: "photo_id[gt]"')
  end

  test "a column not permitted is rejected" do
    assert_unpermitted({ where: { hidden: true } }, 'found unpermitted parameter: "hidden"')
    assert_unpermitted({ where: [{ make: 'Leica' }, 'OR', { hidden: true }] }, 'found unpermitted parameter: "hidden"')
  end

  test "an unknown operator is left to activerecord-filter" do
    # The query runs in the view, which wraps the error
    error = assert_raises(ActionView::Template::Error) do
      get cameras_path(format: :json), params: { limit: 100, where: { make: { bogus: 'Leica' } } }
    end
    assert_instance_of RuntimeError, error.cause
    assert_match(/Not Supported: bogus/, error.cause.message)
  end

  test "AND and OR filters are checked" do
    leica = create(:camera, make: 'Leica')
    sony = create(:camera, make: 'Sony')
    create(:camera, make: 'Canon')

    assert_equal [leica.id, sony.id].sort, ids(where: [{ make: 'Leica' }, 'OR', { make: 'Sony' }])
  end

  test "an association is checked against the associated model's Policy" do
    account = create(:account)
    property = create(:property)
    camera = create(:camera, photo: create(:photo, account: account, properties: [property]))
    create(:camera, photo: create(:photo))

    assert_equal [camera.id], ids(where: { photo: { account_id: account.id } })
    assert_equal [camera.id], ids(where: { photo: { properties: { id: property.id } } })

    assert_unpermitted({ where: { photo: { format: 'jpg' } } }, 'found unpermitted parameter: "format"')
    assert_unpermitted({ where: { photo: { properties: { name: 'a' } } } }, 'found unpermitted parameter: "name"')
  end

  test "an association's _ids is checked against the associated model's Policy" do
    account = create(:account)
    property = create(:property, accounts: [account])
    create(:property)

    get properties_path(format: :json), params: { limit: 100, where: { account_ids: [account.id] } }
    assert_response :ok
    assert_equal [property.id], JSON(response.body).map { |x| x['id'] }

    # PropertyPolicy doesn't make photos filterable
    get properties_path(format: :json), params: { limit: 100, where: { photo_ids: [1] } }
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "photo_ids"', response.body
  end

  test "wheres are rejected when the Policy makes nothing filterable" do
    get references_path(format: :json), params: { limit: 100, where: { id: 1 } }
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "id"', response.body
  end

  # A stand-in Policy::Record that makes +permit+ filterable on +model+
  def policy(model, permit)
    Struct.new(:model, :filterable).new(model, permit)
  end

  test "Wheres#sanitize_wheres checks a polymorphic association against the Policy of its as class" do
    sanitize = AccountsController.new.method(:sanitize_wheres)
    permit = { 'subject' => :all }

    with_model_policy(Property, Class.new(PropertyPolicy) { attribute :id, filterable: false; attribute :name, filterable: true }) do
      assert_equal({ subject: { as: 'Property', name: 'a' } }, sanitize.call({ subject: { as: 'Property', name: 'a' } }, policy(Account, permit)))
      assert_equal({ subject: nil }, sanitize.call({ subject: nil }, policy(Account, permit)))

      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { as: 'Property', id: 1 } }, policy(Account, permit)) }
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { as: 'Camera', hidden: true } }, policy(Account, permit)) }
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { as: 'Kernel' } }, policy(Account, permit)) }
      assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { name: 'a' } }, policy(Account, permit)) }
    end
  end

  test "Wheres#sanitize_wheres" do
    sanitize = CamerasController.new.method(:sanitize_wheres)

    assert_equal({ make: { ilike: 'l%' } }, sanitize.call({ make: { ilike: 'l%' } }, policy(Camera, { 'make' => :all })))
    assert_equal({ make: { ilike: 'l%' } }, sanitize.call({ make: { ilike: 'l%' } }, policy(Camera, { 'make' => ['ilike'] })))
    # An alias is permitted with its canonical name
    assert_equal({ make: { gt: 'l' } }, sanitize.call({ make: { gt: 'l' } }, policy(Camera, { 'make' => ['gt'] })))
    assert_equal({ make: { greater_than: 'l' } }, sanitize.call({ make: { greater_than: 'l' } }, policy(Camera, { 'make' => ['gt'] })))
    assert_equal({ 'make.x' => 'l' }, sanitize.call({ 'make.x' => 'l' }, policy(Camera, { 'make' => :all })))
    assert_equal(1, sanitize.call(1, policy(Camera, { 'id' => :all })))
    assert_nil sanitize.call(nil, policy(Camera, {}))

    # A relative date/time value is not operators
    assert_equal({ make: { at: 'now' } }, sanitize.call({ make: { at: 'now' } }, policy(Camera, { 'make' => ['eq'] })))

    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call(1, policy(Camera, { 'make' => :all })) }
    # An operator listed that activerecord-filter doesn't support only permits itself
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ make: 'l' }, policy(Camera, { 'make' => ['bogus'] })) }
    assert_equal({ make: { bogus: 'l' } }, sanitize.call({ make: { bogus: 'l' } }, policy(Camera, { 'make' => ['bogus'] })))
    # Operators can't be permitted on an association
    assert_raises(StandardAPI::InvalidConfiguration) { sanitize.call({ photo: { id: 1 } }, policy(Camera, { 'photo' => ['eq'] })) }
  end

end
