module StandardAPI
  module RouteHelpers
    
    # Shorthand for adding resources.
    #
    # For example
    #
    #   standard_resources :views
    #
    # Is equivilent to:
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
      end
    end
    
  end
end