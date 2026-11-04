module StandardAPI
  # A Schema that starts from every attribute of the model rather than only
  # those it declares
  class ImplicitSchema < Schema
    implicit_attributes
  end
end
