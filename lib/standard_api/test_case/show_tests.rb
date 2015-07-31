class ActionController::StandardAPI
  
  module ShowTests
    def included(mod)
      mod.send(:include, StandardAPI::TestCase)
    end
  end
  
end