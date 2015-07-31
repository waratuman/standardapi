class ActionController::StandardAPI
  
  module IndexTests
    def included(mod)
      mod.send(:include, StandardAPI::TestCase)
    end
  end
  
end