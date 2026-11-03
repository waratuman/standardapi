module StandardAPI
  module RouteHelpers

    # StandardAPI wrapper for ActionDispatch::Routing::Mapper::Resources#resources
    #
    # Includes the following routes
    #
    #   GET /schema
    #   GET /write_schema
    #   GET /read_schema
    #   GET /query_schema
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
      standard_resource_actions = [ :schema, :write_schema, :read_schema, :query_schema, :calculate, :create_resource, :add_resource, :remove_resource ]

      resources_options = options.deep_dup

      if resources_options[:only]
        resources_options[:only] = Array(resources_options[:only]).map(&:to_sym)
        resources_options[:only].reject! { |a| standard_resource_actions.include?(a) }
      end

      if resources_options[:except]
        resources_options[:except] = Array(resources_options[:except]).map(&:to_sym)
        resources_options[:except].reject! { |a| standard_resource_actions.include?(a) }
      end

      resources(*resources, **resources_options) do
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
        draw_schema_routes(actions)
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
    #   GET /write_schema
    #   GET /read_schema
    #   GET /query_schema
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
      standard_resource_actions = [ :schema, :write_schema, :read_schema, :query_schema, :calculate, :add_resource, :remove_resource ]

      resource_options = options.deep_dup

      if resource_options[:only]
        resource_options[:only] = Array(resource_options[:only]).map(&:to_sym)
        resource_options[:only].reject! { |a| standard_resource_actions.include?(a) }
      end

      if resource_options[:except]
        resource_options[:except] = Array(resource_options[:except]).map(&:to_sym)
        resource_options[:except].reject! { |a| standard_resource_actions.include?(a) }
      end

      resource(*resource, **resource_options) do
        actions = if only = options[:only]
          Array(only).map(&:to_sym)
        else
          if resource_options[:api_only] || (respond_to?(:api_only?) && api_only?)
            [:index, :create, :show, :update, :destroy]
          else
            [:index, :create, :new, :show, :update, :destroy, :edit]
          end + standard_resource_actions
        end

        if except = options[:except]
          actions -= Array(except).map(&:to_sym)
        end

        get :schema, on: :collection if actions.include?(:schema)
        draw_schema_routes(actions)
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

    private

    # Each JSON Schema describes other actions, so is only drawn with them:
    # write_schema with create or update, read_schema with show or index, and
    # query_schema with index or calculate
    def draw_schema_routes(actions)
      if actions.include?(:write_schema) && (actions & [:create, :update]).any?
        get :write_schema, on: :collection
      end
      if actions.include?(:read_schema) && (actions & [:show, :index]).any?
        get :read_schema, on: :collection
      end
      if actions.include?(:query_schema) && (actions & [:index, :calculate]).any?
        get :query_schema, on: :collection
      end
    end

  end
end
