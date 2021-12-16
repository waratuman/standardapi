require 'standard_api/test_helper'

class RouteHelpersTest < ActionDispatch::IntegrationTest

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

  test 'standard_resources subresource routes' do
    assert_routing({ path: '/photos/1/properties/1', method: :post }, { controller: 'photos', action: 'add_resource', id: '1', relationship: 'properties', resource_id: '1' })
    assert_routing({ path: '/photos/1/properties/1', method: :delete }, { controller: 'photos', action: 'remove_resource', id: '1', relationship: 'properties', resource_id: '1' })
  end

  test "standard_resources with only option" do
    with_routing do |set|
      set.draw do
        standard_resources :photos, only: [ :index, :show ]
      end
      assert_routing({ path: '/photos', method: :get }, { controller: 'photos', action: 'index' })
      assert_routing({ path: '/photos/1', method: :get }, { controller: 'photos', action: 'show', id: '1' })
      assert_equal 2, set.routes.size
    end
  end

  test "standard_resources with except option" do
    with_routing do |set|
      set.draw do
        standard_resources :photos, except: [ :destroy ]
      end
      assert_routing({ path: '/photos', method: :get }, { controller: 'photos', action: 'index' })
      assert_routing({ path: '/photos/1', method: :get }, { controller: 'photos', action: 'show', id: '1' })
      assert_routing({ path: '/photos/new', method: :get }, { controller: 'photos', action: 'new' })
      assert_routing({ path: '/photos', method: :post }, { controller: 'photos', action: 'create' })
      assert_routing({ path: '/photos/1', method: :put }, { controller: 'photos', action: 'update', id: '1' })
      assert_routing({ path: '/photos/1', method: :patch }, { controller: 'photos', action: 'update', id: '1' })
      assert_routing({ path: '/photos/schema', method: :get }, { controller: 'photos', action: 'schema' })
      assert_routing({ path: '/photos/calculate', method: :get }, { controller: 'photos', action: 'calculate' })
      assert_routing({ path: '/photos/1/properties/1', method: :post }, { controller: 'photos', action: 'add_resource', id: '1', relationship: 'properties', resource_id: '1' })
      assert_routing({ path: '/photos/1/properties/1', method: :delete }, { controller: 'photos', action: 'remove_resource', id: '1', relationship: 'properties', resource_id: '1' })
      assert_routing({ path: '/photos/1/properties', method: :post }, { controller: 'photos', action: 'create_resource', id: '1', relationship: 'properties' })
      assert_equal 12, set.routes.size
    end
  end

  test "standard_resource with only option" do
    with_routing do |set|
      set.draw do
        standard_resource :accounts, only: :show
      end
      assert_routing({ path: '/accounts', method: :get }, { controller: 'accounts', action: 'show' })
      assert_equal 1, set.routes.size
    end
  end

  test "standard_resource with except option" do
    with_routing do |set|
      set.draw do
        standard_resource :accounts, except: [ :destroy ]
      end
      assert_routing({ path: '/accounts', method: :get }, { controller: 'accounts', action: 'show' })
      assert_routing({ path: '/accounts/new', method: :get }, { controller: 'accounts', action: 'new' })
      assert_routing({ path: '/accounts', method: :post }, { controller: 'accounts', action: 'create' })
      assert_routing({ path: '/accounts', method: :put }, { controller: 'accounts', action: 'update' })
      assert_routing({ path: '/accounts', method: :patch }, { controller: 'accounts', action: 'update' })
      assert_routing({ path: '/accounts/schema', method: :get }, { controller: 'accounts', action: 'schema' })
      assert_routing({ path: '/accounts/calculate', method: :get }, { controller: 'accounts', action: 'calculate' })
      assert_equal 10, set.routes.size
    end
  end
end
