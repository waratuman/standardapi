class ActionController::StandardAPI
  
  module CalculateTests
    def included(mod)
      mod.send(:include, StandardAPI::TestCase)
    end
  end
  
end