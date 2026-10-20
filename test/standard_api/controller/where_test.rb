require 'standard_api/test_helper'

# Wheres are checked against CameraACL#wheres, which permits any operator
# on id and make, eq and in on photo_id, and the photo association, whose
# wheres PhotoACL#wheres permits.
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

  test "an unknown operator is rejected" do
    assert_unpermitted({ where: { make: { bogus: 'Leica' } } }, 'found unpermitted parameter: "make[bogus]"')
  end

  test "AND and OR filters are checked" do
    leica = create(:camera, make: 'Leica')
    sony = create(:camera, make: 'Sony')
    create(:camera, make: 'Canon')

    assert_equal [leica.id, sony.id].sort, ids(where: [{ make: 'Leica' }, 'OR', { make: 'Sony' }])
  end

  test "an association is checked against the associated ACL" do
    account = create(:account)
    property = create(:property)
    camera = create(:camera, photo: create(:photo, account: account, properties: [property]))
    create(:camera, photo: create(:photo))

    assert_equal [camera.id], ids(where: { photo: { account_id: account.id } })
    assert_equal [camera.id], ids(where: { photo: { properties: { id: property.id } } })

    assert_unpermitted({ where: { photo: { format: 'jpg' } } }, 'found unpermitted parameter: "format"')
    assert_unpermitted({ where: { photo: { properties: { name: 'a' } } } }, 'found unpermitted parameter: "name"')
  end

  test "an association's _ids is checked against the associated ACL" do
    account = create(:account)
    property = create(:property, accounts: [account])
    create(:property)

    get properties_path(format: :json), params: { limit: 100, where: { account_ids: [account.id] } }
    assert_response :ok
    assert_equal [property.id], JSON(response.body).map { |x| x['id'] }

    # PropertyACL#wheres does not permit photos
    get properties_path(format: :json), params: { limit: 100, where: { photo_ids: [1] } }
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "photo_ids"', response.body
  end

  test "wheres are rejected without an ACL wheres method" do
    get references_path(format: :json), params: { limit: 100, where: { id: 1 } }
    assert_response :bad_request
    assert_equal 'found unpermitted parameter: "id"', response.body
  end

  test "Wheres#sanitize_wheres checks a polymorphic association against the ACL of its as class" do
    sanitize = Class.new do
      include StandardAPI::Wheres
      private def account_wheres = [:subject]
      private def property_wheres = [:name]
    end.new.method(:sanitize_wheres)

    assert_equal({ subject: { as: 'Property', name: 'a' } }, sanitize.call({ subject: { as: 'Property', name: 'a' } }, [:subject], Account))
    assert_equal({ subject: nil }, sanitize.call({ subject: nil }, [:subject], Account))

    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { as: 'Property', id: 1 } }, [:subject], Account) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { as: 'Camera', make: 'a' } }, [:subject], Account) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { as: 'Kernel' } }, [:subject], Account) }
    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call({ subject: { name: 'a' } }, [:subject], Account) }
  end

  test "Wheres#sanitize_wheres" do
    sanitize = CamerasController.new.method(:sanitize_wheres)

    assert_equal({ make: { ilike: 'l%' } }, sanitize.call({ make: { ilike: 'l%' } }, [{ make: '*' }], Camera))
    assert_equal({ make: { ilike: 'l%' } }, sanitize.call({ make: { ilike: 'l%' } }, [{ make: :ilike }], Camera))
    # Aliases permit each other
    assert_equal({ make: { gt: 'l' } }, sanitize.call({ make: { gt: 'l' } }, [{ make: [:greater_than] }], Camera))
    assert_equal({ make: { greater_than: 'l' } }, sanitize.call({ make: { greater_than: 'l' } }, [{ make: [:gt] }], Camera))
    assert_equal({ 'make.x' => 'l' }, sanitize.call({ 'make.x' => 'l' }, [:make], Camera))
    assert_equal(1, sanitize.call(1, [:id], Camera))
    assert_nil sanitize.call(nil, [], Camera)

    # A relative date/time value is not operators
    assert_equal({ make: { at: 'now' } }, sanitize.call({ make: { at: 'now' } }, [{ make: :eq }], Camera))

    assert_raises(StandardAPI::UnpermittedParameters) { sanitize.call(1, [:make], Camera) }
    assert_raises(StandardAPI::InvalidConfiguration) { sanitize.call({ make: 'l' }, [{ make: :bogus }], Camera) }
    # Operators can't be permitted on an association
    assert_raises(StandardAPI::InvalidConfiguration) { sanitize.call({ photo: { id: 1 } }, [{ photo: [:eq] }], Camera) }
  end

end
