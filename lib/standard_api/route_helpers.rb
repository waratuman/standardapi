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
      standard_resource_actions = [ :schema, :calculate, :create_resource, :add_resource, :remove_resource ]

      resources_options = options.deep_dup

      if resources_options[:only]
        resources_options[:only] = Array(resources_options[:only]).map(&:to_sym)
        resources_options[:only].reject! { |a| standard_resource_actions.include?(a) }
      end

      if resources_options[:except]
        resources_options[:except] = Array(resources_options[:except]).map(&:to_sym)
        resources_options[:except].reject! { |a| standard_resource_actions.include?(a) }
      end

      resources(*resources, resources_options) do
        block.call if block # custom routes take precedence over standardapi routes

        actions = parent_resource.actions + standard_resource_actions

        if only = options[:only]
          only = Array(only).map(&:to_sym)
          actions.select! { |a| only.include?(a) }
        end

        if except = options[:except]
          except = Array(except).map(&:to_sym)
          actions.reject! { |a| except.include?(a) }
        end

        get :schema, on: :collection if actions.include?(:schema)
        get :calculate, on: :collection if actions.include?(:calculate)

        if actions.include?(:add_resource)
          post ':relationship/:resource_id' => :add_resource, on: :member
        end

        if actions.include?(:create_resource)
          post ':relationship' => :create_resource, on: :member
        end

        if actions.include?(:remove_resource)
          delete ':relationship/:resource_id' => :remove_resource, on: :member
        end
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
