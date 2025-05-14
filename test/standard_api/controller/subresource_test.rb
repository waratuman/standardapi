require 'standard_api/test_helper'

class ControllerSubresourceTest < ActionDispatch::IntegrationTest
  
  # add_resource
  test 'Controller#add_resource with has_many' do
    property = create(:property, photos: [])
    photo = create(:photo)

    post "/properties/#{property.id}/photos/#{photo.id}"
    assert_equal property.photos.reload.map(&:id), [photo.id]
    assert_response :created

    assert_raises ActiveRecord::RecordNotFound do
      post "/properties/#{property.id}/photos/9999999"
    end
  end

  test 'Controller#add_resource with has_and_belongs_to_many' do
    photo1 = create(:photo)
    photo2 = create(:photo)
    property = create(:property, photos: [photo1])

    post "/properties/#{property.id}/photos/#{photo2.id}"
    assert_equal property.photos.reload.map(&:id), [photo1.id, photo2.id]
    assert_response :created

    assert_raises ActiveRecord::RecordNotFound do
      post "/properties/#{property.id}/photos/9999999"
    end
  end

  test 'Controller#add_resource with belongs_to' do
    photo = create(:photo)
    account = create(:account)

    post "/photos/#{photo.id}/account/#{account.id}"
    assert_equal photo.reload.account_id, account.id
    assert_response :created
  end

  test 'Controller#add_resource with has_one' do
    photo = create(:document)
    property = create(:property)
    post "/properties/#{property.id}/document/#{photo.id}"
    assert_equal property.reload.document, photo
    assert_response :created
  end
  
  test 'Controller#add_resource that is already there' do
    photo = create(:photo)
    property = create(:property, photos: [photo])

    post "/properties/#{property.id}/photos/#{photo.id}"
    assert_response :bad_request
    assert_equal JSON(response.body), {
      "errors" => [
        "Relationship between Property and Photo violates unique constraints"
      ]
    }

    assert_raises ActiveRecord::RecordNotFound do
      post "/properties/#{property.id}/photos/9999999"
    end
  end

  # create_resource
  test 'Controller#create_resource with has_many' do
    property = create(:property, photos: [])
    photo = build(:photo)

    post "/properties/#{property.id}/photos", params: { photo: photo.attributes }, as: :json
    assert_equal property.photos.reload.map(&:id), [JSON.parse(response.body)['id']]
    assert_equal property.photos.count, 1
    assert_response :created
  end

  test 'Controller#create_resource with has_and_belongs_to_many' do
    photo1 = create(:photo)
    photo2 = build(:photo)
    property = create(:property, photos: [photo1])

    post "/properties/#{property.id}/photos", params: { photo: photo2.attributes }, as: :json
    assert_equal property.photos.reload.map(&:id).sort, [photo1.id, JSON.parse(response.body)['id']].sort
    assert_equal property.photos.count, 2
    assert_response :created
  end

  test 'Controller#create_resource with belongs_to' do
    photo = create(:photo)
    account = build(:account)

    post "/photos/#{photo.id}/account", params: { account: account.attributes }, as: :json
    assert_equal photo.reload.account_id, JSON.parse(response.body)['id']
    assert_response :created
  end

  test 'Controller#create_resource with has_one' do
    account = build(:account)
    property = create(:property)
    post "/properties/#{property.id}/landlord", params: { account: account.attributes }, as: :json
    assert_equal property.reload.landlord.id, JSON.parse(response.body)['id']
    assert_equal property.reload.landlord.name, account.name
    assert_response :created
  end

  # remove_resource
  test 'Controller#remove_resource' do
    photo = create(:photo)
    property = create(:property, photos: [photo])
    assert_equal property.photos.reload, [photo]
    delete "/properties/#{property.id}/photos/#{photo.id}"
    assert_equal property.photos.reload, []
    assert_response :no_content

    assert_raises ActiveRecord::RecordNotFound do
      delete "/properties/#{property.id}/photos/9999999"
    end
  end

  test 'Controller#remove_resource with has_one' do
    photo = create(:document)
    property = create(:property, document: photo)
    assert_equal property.document, photo
    delete "/properties/#{property.id}/document/#{photo.id}"
    assert_nil property.reload.document
    assert_response :no_content
  end

  test 'Controller#remove_resource with belongs_to' do
    account = create(:account)
    photo = create(:photo, account: account)

    delete "/photos/#{photo.id}/account/#{account.id}"
    assert_nil photo.reload.account_id
    assert_response :no_content
  end

  test 'Controller#remove_resource with belongs_to unless not match' do
    account1 = create(:account)
    account2 = create(:account)
    photo = create(:photo, account: account1)

    delete "/photos/#{photo.id}/account/#{account2.id}"
    assert_equal photo.reload.account_id, account1.id
    assert_response :not_found
  end

  test 'Controller#remove_resource with belongs_to unless not match and is nil' do
    account = create(:account)
    photo = create(:photo)

    delete "/photos/#{photo.id}/account/#{account.id}"
    assert_nil photo.reload.account_id
    assert_response :not_found
  end

end
