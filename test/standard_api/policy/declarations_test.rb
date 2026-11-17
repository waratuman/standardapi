require 'standard_api/test_helper'

class PolicyDeclarationsTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  KEYS = %i(name type enum default primary_key null array comment
    auto_populated read_only required validations)

  test 'only declared attributes are used, in attribute order' do
    policy = empty_policy_class do
      attributes :make, :id
      attribute :thumbnail_url, :string
    end

    assert_equal ['id', 'make', 'thumbnail_url'], names(policy)
  end

  test 'declaring nothing uses nothing' do
    assert_empty names(empty_policy_class)
  end

  test 'a declared attribute keeps what the model says about it' do
    make = definition(empty_policy_class { attributes :make }, 'make')

    assert_equal 'string', make[:type]
    assert_equal false, make[:null]
    assert_equal KEYS, make.keys
  end

  test 'a new column stays hidden until it is declared' do
    camera = create(:camera)
    policy = empty_policy_class { attributes :id, :make }

    with_policy(policy) do
      get camera_path(camera, format: 'json')
      assert_response :ok
      assert_equal ['id', 'make'], JSON(response.body).keys.sort

      get read_schema_cameras_path(format: 'json')
      assert_equal ['errors', 'id', 'make'], JSON(response.body)['properties'].keys.sort
    end
  end

  test 'a select the Policy does not declare is not rendered' do
    camera = create(:camera)
    selected = Camera.select('cameras.*, 1 AS rank').find(camera.id)

    assert_equal ['id'], names(empty_policy_class { attributes :id }, selected)
    assert_equal ['id', 'rank'], names(empty_policy_class { attributes :id; attribute :rank, :integer }, selected)
  end

  test 'attributes declared at runtime count as declared' do
    policy = empty_policy_class do
      attributes :id
      attributes_for(-> { :all }) { attributes :make }
    end

    assert_equal ['id', 'make'], names(policy)
  end

  test 'attributes raises for an attribute the model lacks' do
    error = assert_raises(ArgumentError) { definitions(empty_policy_class { attributes :mkae }) }
    assert_match(/Camera has no attribute mkae/, error.message)
  end

  test 'attribute and remove declare at runtime too' do
    policy = empty_policy_class do
      attributes :id, :make
      attributes_for(-> { :all }) do
        attribute :thumbnail_url, :string
        remove :make
      end
    end

    assert_equal ['id', 'thumbnail_url'], names(policy)
  end

  test 'attribute changes a definition in place' do
    policy = policy_class { attribute :make, comment: 'Who made it', read_only: true }

    assert_equal Camera.attribute_names, names(policy)
    assert_equal 'Who made it', definition(policy, 'make')[:comment]
    assert_equal true, definition(policy, 'make')[:read_only]
    assert_equal 'string', definition(policy, 'make')[:type]
  end

  test 'attribute changes a type' do
    assert_equal 'text', definition(policy_class { attribute :make, :text }, 'make')[:type]
  end

  test 'attribute with a type adds a definition with every key, read only' do
    policy = policy_class { attribute :thumbnail_url, :string, comment: 'A thumbnail' }

    assert_equal Camera.attribute_names + ['thumbnail_url'], names(policy)
    added = definition(policy, 'thumbnail_url')
    assert_equal KEYS, added.keys
    assert_equal({
      name: 'thumbnail_url', type: 'string', enum: nil, default: nil,
      primary_key: false, null: true, array: false, comment: 'A thumbnail',
      auto_populated: false, read_only: true, required: false, validations: []
    }, added)
  end

  test 'attribute without a type raises for an attribute the model lacks' do
    error = assert_raises(ArgumentError) { definitions(policy_class { attribute :mkae, comment: 'Typo' }) }
    assert_match(/Camera has no attribute mkae/, error.message)
  end

  test 'attribute raises for an unknown option' do
    error = assert_raises(ArgumentError) { definitions(policy_class { attribute :make, commnet: 'Typo' }) }
    assert_match(/unknown options for attribute make: commnet/, error.message)
  end

  test "attribute doesn't add a real attribute the query didn't select" do
    camera = create(:camera)
    policy = policy_class do
      attribute :make, :string, comment: 'Who made it'
      attribute :thumbnail_url, :string
    end

    assert_equal ['id', 'thumbnail_url'], names(policy, Camera.select(:id).find(camera.id))
  end

  test "declarations don't change the shared default definitions" do
    defaults = [{ name: 'make', type: 'string', comment: nil }.freeze].freeze
    builder = StandardAPI::Policy::Builder.new.attribute(:make, comment: 'Who made it').remove(:retired)

    assert_equal [{ name: 'make', type: 'string', comment: 'Who made it' }], builder.apply(defaults, Camera)
  end

  test 'remove takes back a declaration' do
    assert_equal Camera.attribute_names - ['make', 'retired'], names(policy_class { remove :make, :retired })
  end

  test 'remove takes back what a parent declares, without changing it' do
    parent = empty_policy_class { attributes :id, :make }
    child = Class.new(parent) { remove :make }

    assert_equal ['id'], names(child)
    assert_equal ['id', 'make'], names(parent)
  end

  test 'the last declaration of an attribute wins' do
    assert_includes names(policy_class { remove :make; attribute :make, comment: 'Back' }), 'make'
    assert_not_includes names(policy_class { attribute :make, comment: 'Gone'; remove :make }), 'make'
  end

  test 'a subclass inherits declarations without changing its parent' do
    parent = policy_class { attribute :thumbnail_url, :string }
    child = Class.new(parent) { attribute :preview_url, :string }

    assert_includes names(child), 'thumbnail_url'
    assert_includes names(child), 'preview_url'
    assert_not_includes names(parent), 'preview_url'
  end

end
