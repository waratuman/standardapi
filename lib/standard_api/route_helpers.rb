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
        available_actions = if only = parent_resource.instance_variable_get(:@only)
          Array(only).map(&:to_sym)
        else
          if parent_resource.instance_variable_get(:@api_only)
            [:index, :create, :show, :update, :destroy]
          else
            [:index, :create, :new, :show, :update, :destroy, :edit]
          end + [ :schema, :calculate, :add_resource, :remove_resource ]
        end

        actions = if except = parent_resource.instance_variable_get(:@except)
          available_actions - Array(except).map(&:to_sym)
        else
          available_actions
        end

        get :schema, on: :collection if actions.include?(:schema)
        get :calculate, on: :collection if actions.include?(:calculate)

        if actions.include?(:add_resource)
          post ':relationship/:resource_id' => :add_resource, on: :member
        end

        if actions.include?(:remove_resource)
          delete ':relationship/:resource_id' => :remove_resource, on: :member
        end

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
        available_actions = if only = parent_resource.instance_variable_get(:@only)
          Array(only).map(&:to_sym)
        else
          if parent_resource.instance_variable_get(:@api_only)
            [:index, :create, :show, :update, :destroy]
          else
            [:index, :create, :new, :show, :update, :destroy, :edit]
          end + [ :schema, :calculate, :add_resource, :remove_resource ]
        end

        actions = if except = parent_resource.instance_variable_get(:@except)
          available_actions - Array(except).map(&:to_sym)
        else
          available_actions
        end

        get :schema, on: :collection if actions.include?(:schema)
        get :calculate, on: :collection if actions.include?(:calculate)

        if actions.include?(:add_resource)
          post ':relationship/:resource_id' => :add_resource, on: :member
        end

        if actions.include?(:remove_resource)
          delete ':relationship/:resource_id' => :remove_resource, on: :member
        end

        block.call if block
      end
    end

  end
end
