class ActionController::StandardAPI
  
  module DestroyTests
    def included(mod)
      mod.send(:include, StandardAPI::TestCase)
    end
  end
  
end