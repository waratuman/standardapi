class ActionDispatch::Routing::Mapper::Resources::Resource

  class << self
    def default_actions(api_only)
      if api_only
        [:index, :create, :show, :update, :destroy, :schema]
      else
        [:index, :create, :new, :show, :update, :destroy, :edit, :schema]
      end
    end
  end

end
