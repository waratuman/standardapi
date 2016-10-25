require 'test_helper'

class RouteHelpersTest < ActionDispatch::IntegrationTest
  include StandardAPI::RouteHelpers

  test 'standard_resources' do
    assert_routing({ path: '/properties', method: :get }, { controller: 'properties', action: 'index' })
    assert_routing({ path: '/properties/1', method: :get }, { controller: 'properties', action: 'show', id: '1' })
    assert_routing({ path: '/properties/new', method: :get }, { controller: 'properties', action: 'new' })
    assert_routing({ path: '/properties', method: :post }, { controller: 'properties', action: 'create' })
    assert_routing({ path: '/properties/1', method: :put }, { controller: 'properties', action: 'update', id: '1' })
    assert_routing({ path: '/properties/1', method: :patch }, { controller: 'properties', action: 'update', id: '1' })
    assert_routing({ path: '/properties/1', method: :delete }, { controller: 'properties', action: 'destroy', id: '1' })
    assert_routing({ path: '/properties/schema', method: :get }, { controller: 'properties', action: 'schema' })
    assert_routing({ path: '/properties/calculate', method: :get }, { controller: 'properties', action: 'calculate' })
  end

  test 'standard_resource' do
    assert_routing({ path: '/account', method: :get }, { controller: 'accounts', action: 'show' })
    assert_routing({ path: '/account/new', method: :get }, { controller: 'accounts', action: 'new' })
    assert_routing({ path: '/account', method: :post }, { controller: 'accounts', action: 'create' })
    assert_routing({ path: '/account', method: :put }, { controller: 'accounts', action: 'update' })
    assert_routing({ path: '/account', method: :patch }, { controller: 'accounts', action: 'update' })
    assert_routing({ path: '/account', method: :delete }, { controller: 'accounts', action: 'destroy' })
    assert_routing({ path: '/account/schema', method: :get }, { controller: 'accounts', action: 'schema' })
    assert_routing({ path: '/account/calculate', method: :get }, { controller: 'accounts', action: 'calculate' })
  end

end