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
    
    with_routing do |set|
      set.draw do
        standard_resources :photos, only: [ :schema ]
      end
      assert_routing({ path: '/photos/schema', method: :get }, { controller: 'photos', action: 'schema' })
      assert_equal 1, set.routes.size
    end

  end

  test "standard_resources only draws a JSON Schema with the actions it describes" do
    with_routing do |set|
      set.draw do
        standard_resources :photos, only: [ :write_schema, :read_schema, :query_schema ]
      end
      assert_equal 0, set.routes.size
    end

    with_routing do |set|
      set.draw do
        standard_resources :photos, only: [ :show, :write_schema, :read_schema, :query_schema ]
      end
      assert_routing({ path: '/photos/read_schema', method: :get }, { controller: 'photos', action: 'read_schema' })
      assert_equal ['/photos/:id(.:format)', '/photos/read_schema(.:format)'], set.routes.map { |r| r.path.spec.to_s }.sort
    end

    with_routing do |set|
      set.draw do
        standard_resources :photos, only: [ :update, :calculate, :write_schema, :read_schema, :query_schema ]
      end
      assert_routing({ path: '/photos/write_schema', method: :get }, { controller: 'photos', action: 'write_schema' })
      assert_routing({ path: '/photos/query_schema', method: :get }, { controller: 'photos', action: 'query_schema' })
      assert set.routes.none? { |r| r.path.spec.to_s.start_with?('/photos/read_schema') }
    end

    with_routing do |set|
      set.draw do
        standard_resource :account, only: [ :create, :write_schema, :read_schema, :query_schema ]
      end
      assert_routing({ path: '/account/write_schema', method: :get }, { controller: 'accounts', action: 'write_schema' })
      assert set.routes.none? { |r| r.path.spec.to_s =~ %r{/account/(read|query)_schema} }
    end
  end

  test "json_schema is no longer drawn" do
    assert Rails.application.routes.routes.none? { |r| r.path.spec.to_s.include?('json_schema') }
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
      assert_routing({ path: '/photos/write_schema', method: :get }, { controller: 'photos', action: 'write_schema' })
      assert_routing({ path: '/photos/read_schema', method: :get }, { controller: 'photos', action: 'read_schema' })
      assert_routing({ path: '/photos/query_schema', method: :get }, { controller: 'photos', action: 'query_schema' })
      assert_routing({ path: '/photos/calculate', method: :get }, { controller: 'photos', action: 'calculate' })
      assert_routing({ path: '/photos/1/properties/1', method: :post }, { controller: 'photos', action: 'add_resource', id: '1', relationship: 'properties', resource_id: '1' })
      assert_routing({ path: '/photos/1/properties/1', method: :delete }, { controller: 'photos', action: 'remove_resource', id: '1', relationship: 'properties', resource_id: '1' })
      assert_routing({ path: '/photos/1/properties', method: :post }, { controller: 'photos', action: 'create_resource', id: '1', relationship: 'properties' })
      assert_equal 15, set.routes.size
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
      assert_routing({ path: '/accounts/write_schema', method: :get }, { controller: 'accounts', action: 'write_schema' })
      assert_routing({ path: '/accounts/read_schema', method: :get }, { controller: 'accounts', action: 'read_schema' })
      assert_routing({ path: '/accounts/query_schema', method: :get }, { controller: 'accounts', action: 'query_schema' })
      assert_routing({ path: '/accounts/calculate', method: :get }, { controller: 'accounts', action: 'calculate' })
      assert_equal 13, set.routes.size
    end
  end
end
