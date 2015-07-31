class ActionController::StandardAPI
  
  module CreateTests
    def included(mod)
      mod.send(:include, StandardAPI::TestCase)
    end
  end
  
end