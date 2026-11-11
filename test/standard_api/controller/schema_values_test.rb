require 'standard_api/test_helper'

class ControllerSchemaValuesTest < ActionDispatch::IntegrationTest

  def show_camera(camera)
    get "/cameras/#{camera.id}", as: :json
    assert_response :ok
    JSON(response.body)
  end

  test 'value renders in place of the attribute of the record' do
    camera = create(:camera, make: 'Leica')

    with_camera_schema(-> { attribute :make, value: -> { record.make.upcase } }) do
      assert_equal 'LEICA', show_camera(camera)['make']
    end
    assert_equal 'Leica', show_camera(camera)['make']
  end

  test 'value can name a method of the Schema' do
    camera = create(:camera, make: 'Leica')

    declarations = -> {
      attribute :label, :string, value: :label
      define_method(:label) { "#{record.make} ##{record.id}" }
      private :label
    }
    with_camera_schema(declarations) do
      assert_equal "Leica ##{camera.id}", show_camera(camera)['label']
    end
  end

  test 'remove takes back a value' do
    camera = create(:camera, make: 'Leica')

    with_camera_schema(-> { attribute :make, value: -> { 'Other' }; remove :make; attribute :make }) do
      assert_equal 'Leica', show_camera(camera)['make']
    end
  end

  test 'a value makes the Schema vary by requester' do
    assert Class.new(StandardAPI::Schema) { attribute :make, value: -> { 'x' } }.varies_by_requester?
  end

  test 'a value that is not a Symbol or Proc raises' do
    assert_raises(ArgumentError) { Class.new(StandardAPI::Schema) { attribute :make, value: 'x' } }
  end

end
