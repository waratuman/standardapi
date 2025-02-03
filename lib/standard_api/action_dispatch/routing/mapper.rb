class ActionDispatch::Routing::Mapper::Resources::Resource

  class << self
    def default_actions(api_only)
      if api_only
        [:index, :create, :show, :update, :destroy]
      else
        [:index, :create, :new, :show, :update, :destroy, :edit]
      end + [ :schema, :calculate, :add_resource, :remove_resource, :create_resource ]
    end
  end

end
