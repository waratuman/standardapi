class ActionController::StandardAPI
  
  module UpdateTests
    def included(mod)
      mod.send(:include, StandardAPI::TestCase)
    end
  end
  
end