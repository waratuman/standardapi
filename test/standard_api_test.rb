require 'test_helper'

class PropertiesControllerTest < ActionController::TestCase
  include StandardAPI::TestCase

  # = Routing Tests
  # These also can't be included in StandardAPI::TestCase because we don't know
  # how the other's routes are setup
  test 'route to #create.json' do
    assert_routing({ method: :post, path: "/#{plural_name}" }, path_with_action('create'))
    assert_recognizes(path_with_action('create'), { method: :post, path: "/#{plural_name}" })
  end

  test 'route to #calculate.json' do
    assert_routing "/#{plural_name}/calculate", path_with_action('calculate')
    assert_recognizes(path_with_action('calculate'), "/#{plural_name}/calculate")
  end

  test 'route to #destroy.json' do
    assert_routing({ method: :delete, path: "/#{plural_name}/1" }, path_with_action('destroy', id: '1'))
    assert_recognizes(path_with_action('destroy', id: '1'), { method: :delete, path: "/#{plural_name}/1" })
  end

  test 'route to #index.json' do
    assert_routing "/#{plural_name}", path_with_action('index')
    assert_recognizes path_with_action('index'), "/#{plural_name}"
  end

  test 'route to #show.json' do
    assert_routing "/#{plural_name}/1", path_with_action('show', id: '1')
    assert_recognizes(path_with_action('show', id: '1'), "/#{plural_name}/1")
  end

  test 'route to #update.json' do
    assert_routing({ method: :put, path: "#{plural_name}/1" }, path_with_action('update', id: '1'))
    assert_recognizes(path_with_action('update', id: '1'), { method: :put, path: "/#{plural_name}/1" })
    assert_routing({ method: :patch, path: "/#{plural_name}/1" }, path_with_action('update', id: '1'))
    assert_recognizes(path_with_action('update', id: '1'), { method: :patch, path: "/#{plural_name}/1" })
  end

end
