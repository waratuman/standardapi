class ActionController::StandardAPI
  
  module ControllerTest

  end
  
end

require File.expand_path(File.join(__FILE__, '../test_case/calculate_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/create_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/destroy_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/index_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/show_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/update_tests'))