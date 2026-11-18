require 'standard_api/test_helper'

class PolicyWritablePolicyTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  # Only a photo's format can be written through it
  FormatOnlyPolicy = Class.new(StandardAPI::Policy) { attributes :id, :format, writable: true }

  def policy_for(policy)
    policy.new(PropertiesController.new, Property)
  end

  test 'writable: { policy: } gives the Policy the associated records are written with' do
    policy = empty_policy_class do
      association :photos, writable: { policy: FormatOnlyPolicy }
      association :accounts, writable: true
    end

    assert_equal FormatOnlyPolicy, policy_for(policy).writable_policy(nil, :photos)
    assert_nil policy_for(policy).writable_policy(nil, :accounts)
  end

  test 'an association that renders with policy: raises unless writable says which Policy writes it' do
    error = assert_raises(ArgumentError) do
      empty_policy_class { association :photos, policy: FormatOnlyPolicy, writable: true }
    end
    assert_match(/association photos renders with policy:, so say which Policy writes it with writable: \{ policy: \}/, error.message)

    assert_nothing_raised do
      empty_policy_class { association :photos, policy: FormatOnlyPolicy, writable: { policy: PhotoPolicy } }
      empty_policy_class { association :photos, policy: FormatOnlyPolicy, writable: { policy: FormatOnlyPolicy } }
      empty_policy_class { association :photos, policy: FormatOnlyPolicy }
    end
  end

  test 'one declared apart raises when it is first written' do
    policy = empty_policy_class do
      association :photos, policy: -> { FormatOnlyPolicy }
      writable :photos
    end

    error = assert_raises(ArgumentError) { policy_for(policy).permitted_associations(nil) }
    assert_match(/association photos of Property renders with policy:/, error.message)

    policy = Class.new(policy) { writable :photos, policy: PhotoPolicy }
    assert_equal %w[photos], policy_for(policy).permitted_associations(nil)
  end

  test 'a writable policy must be a Policy class, and only for an association' do
    assert_raises(ArgumentError) { empty_policy_class { association :photos, writable: { policy: -> { PhotoPolicy } } } }
    assert_raises(ArgumentError) { empty_policy_class { association :photos, writable: { policy: Photo } } }
    assert_raises(ArgumentError) { empty_policy_class { attribute :name, writable: { policy: PhotoPolicy } } }

    policy = empty_policy_class { writable :name, policy: PhotoPolicy }
    error = assert_raises(ArgumentError) { policy_for(policy).permitted_attributes(nil) }
    assert_match(/name of Property isn't an association/, error.message)
  end

  test 'POST create writes the associated records with the writable policy' do
    account = create(:account)
    policy = Class.new(PropertyPolicy) { association :photos, writable: { policy: FormatOnlyPolicy } }

    with_model_policy(Property, policy) do
      post properties_path, params: { property: { name: 'Hancock', photos: [{ format: 'jpg', account_id: account.id }] } }, as: :json
    end

    assert_response :created
    photo = Property.last.photos.sole
    assert_equal ['jpg', nil], [photo.format, photo.account_id]
  end

  test 'writing with a policy other than its own raises when the associated model has an ACL filter' do
    ApplicationController.class_eval { def filter_photo_params(photo, params, **options) = filter_model_params(photo, params, **options) }
    policy = Class.new(PropertyPolicy) { association :photos, writable: { policy: FormatOnlyPolicy } }

    with_model_policy(Property, policy) do
      error = assert_raises(StandardAPI::InvalidConfiguration) do
        post properties_path, params: { property: { name: 'Hancock', photos: [{ format: 'jpg' }] } }, as: :json
      end
      assert_match(/Property#photos is written with .*FormatOnlyPolicy, but Photo has an ACL filter/, error.message)
    end
  ensure
    ApplicationController.send(:remove_method, :filter_photo_params)
  end

end
