require 'standard_api/test_helper'

class PolicyFilterableTest < ActionDispatch::IntegrationTest
  include PolicyTestHelper

  def filterable(policy, model = Camera)
    policy.new(CamerasController.new, model).permitted_wheres
  end

  test 'filterable is what attributes and associations declare filterable' do
    policy = empty_policy_class do
      attributes :id, :make, filterable: true
      attribute :created_at
      association :photo, filterable: true
      association :specs
    end

    assert_equal({ 'id' => :all, 'make' => :all, 'photo' => :all }, filterable(policy))
  end

  test 'filterable lists the operators it permits, by their canonical names' do
    policy = empty_policy_class do
      attribute :id, filterable: [:eq, :in]
      attribute :make, filterable: :greater_than
      attribute :photo_id, filterable: '*'
    end

    assert_equal({ 'id' => ['eq', 'in'], 'make' => ['gt'], 'photo_id' => :all }, filterable(policy))
  end

  test 'an association can only be filterable: true' do
    assert_raises(ArgumentError) { empty_policy_class { association :photo, filterable: [:eq] } }
  end

  test 'filterable declares names without rendering them' do
    policy = empty_policy_class do
      attribute :id
      filterable :make, :search
      filterable :photo_id, operators: [:eq]
    end

    assert_equal({ 'make' => :all, 'search' => :all, 'photo_id' => ['eq'] }, filterable(policy))
    assert_equal ['id'], names(policy)
  end

  test 'filterable raises for an unknown option' do
    assert_raises(ArgumentError) { filterable(empty_policy_class { filterable :make, bogus: true }) }
  end

  test 'filterable: false takes back an inherited one, as does remove' do
    parent = empty_policy_class do
      attributes :id, :make, filterable: true
      filterable :search
    end

    assert_equal({ 'id' => :all, 'search' => :all }, filterable(Class.new(parent) { attribute :make, filterable: false }))
    assert_equal({ 'id' => :all, 'make' => :all }, filterable(Class.new(parent) { remove :search }))
  end

  test 'filterable leaves out what a condition hides from the model' do
    policy = empty_policy_class do
      attribute :id, filterable: true
      attribute :make, filterable: true, if: -> { record&.persisted? }
      association :photo, filterable: true, unless: -> { true }
      filterable :search, if: -> { params[:search] }
      filterable :hidden, unless: :retired?
    end
    controller = CamerasController.new
    controller.params = ActionController::Parameters.new(search: '1')
    controller.define_singleton_method(:retired?) { true }

    assert_equal({ 'id' => :all, 'search' => :all }, policy.new(controller, Camera).permitted_wheres)
  end

  test 'filterable includes what attributes_for declares for the model' do
    policy = empty_policy_class do
      attributes_for(-> { :key }) { |key| filterable :make if key == :key }
    end

    assert_equal({ 'make' => :all }, filterable(policy))
  end

  test 'filterable does not make the Policy vary by requester' do
    assert_not empty_policy_class { filterable :make, if: -> { true } }.varies_by_requester?
  end

  test 'GET index filters on what the Policy makes filterable' do
    leica = create(:camera, make: 'Leica')
    create(:camera, make: 'Sony')

    with_camera_policy(proc { attribute :make, filterable: false; filterable :make, operators: [:eq] }) do
      get cameras_path(format: 'json'), params: { where: { make: 'Leica' }, limit: 10 }
      assert_response :ok
      assert_equal [leica.id], JSON(response.body).map { |c| c['id'] }

      get cameras_path(format: 'json'), params: { where: { make: { like: 'L%' } }, limit: 10 }
      assert_response :bad_request
    end
  end

end
