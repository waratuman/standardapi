module StandardAPI
  module RouteHelpers
    
    # StandardAPI wrapper for ActionDispatch::Routing::Mapper::Resources#resources
    #
    # Includes the following routes
    #   
    #   GET /schema
    #   GET /calculate
    #
    # For example
    #
    #   standard_resources :views
    #
    # is equivilent to:
    #
    #   resources :api_keys do
    #     get :schema, on: :collection
    #     get :calculate, on: :collection
    #   end
    def standard_resources(*resources, &block)
      options = resources.extract_options!.dup
      
      resources(*resources, options) do
        get :schema, on: :collection
        get :calculate, on: :collection
        post ':relationship/:resource_id/remove' => :remove_resource, on: :member
        post ':relationship/:resource_id/add' => :add_resource, on: :member
        block.call if block
      end
    end

    # StandardAPI wrapper for ActionDispatch::Routing::Mapper::Resources#resource
    #
    # Includes the following routes
    #   
    #   GET /schema
    #   GET /calculate
    #
    # For example:
    #
    #   standard_resource :account
    #
    # is equivilent to:
    #
    #   resource :account do
    #     get :schema, on: :collection
    #     get :calculate, on: :collection
    #   end
    def standard_resource(*resource, &block)
      options = resource.extract_options!.dup
      
      resource(*resource, options) do
        get :schema, on: :collection
        get :calculate, on: :collection
        post ':relationship/:resource_id/remove' => :remove_resource, on: :member
        post ':relationship/:resource_id/add' => :add_resource, on: :member
        block.call if block
      end
    end

  end
end
