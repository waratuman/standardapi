require 'standard_api/test_helper'

class ControllerSubresourceTest < ActionDispatch::IntegrationTest

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

end
