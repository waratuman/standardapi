require 'standard_api/test_helper'

class PolicySchemaTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  def camera_json(path)
    get "/cameras/#{path}", params: { format: 'json' }
    assert_response :ok
    JSON(response.body)
  end

  test 'schema.json lists only what the Policy declares' do
    policy = empty_policy_class do
      attributes :id, :make
      attribute :hidden, if: -> { false }
      attribute :thumbnail_url, :string, comment: 'Small'
    end

    with_policy(policy) do
      attributes = camera_json('schema')['attributes']
      assert_equal ['id', 'make', 'thumbnail_url'], attributes.keys
      assert_equal 'string', attributes.dig('thumbnail_url', 'type')
      assert_equal 'Small', attributes.dig('thumbnail_url', 'comment')
      assert_equal true, attributes.dig('thumbnail_url', 'readonly')
    end
  end

  test 'schema.json uses a type the Policy declares for a column' do
    policy = empty_policy_class { attribute :make, :integer }

    with_policy(policy) do
      assert_equal 'integer', camera_json('schema').dig('attributes', 'make', 'type')
    end
  end

  test 'schema.json at the root lists only what the Policy declares' do
    with_policy(empty_policy_class { attributes :id }) do
      get '/schema', params: { format: 'json' }
      assert_response :ok
      assert_equal ['id'], JSON(response.body).dig('models', 'Camera', 'attributes').keys
    end
  end

  test 'schema.json and schema/write.json follow a declared read_only' do
    policy = empty_policy_class do
      attribute :photo_id, read_only: true
      attribute :id, read_only: false
      attributes :make
    end

    with_policy(policy) do
      attributes = camera_json('schema')['attributes']
      assert_equal true, attributes.dig('photo_id', 'readonly')
      assert_equal false, attributes.dig('id', 'readonly')

      # CameraACL permits photo_id and make, but not id
      properties = camera_json('schema/write').dig('properties', 'camera', 'properties')
      assert_equal true, properties.dig('photo_id', 'readOnly')
      assert_nil properties.dig('make', 'readOnly')
    end
  end

  test 'schema/read.json, write.json and query.json are not found for a controller without a model' do
    assert_nil SessionsController.model

    %w(read write query).each do |kind|
      get "/sessions/schema/#{kind}.json"
      assert_response :not_found, kind
    end
  end

end
