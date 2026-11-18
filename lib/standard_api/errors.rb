module StandardAPI
  class StandardAPIError < StandardError
  end

  class ParameterMissing < StandardAPIError
    attr_reader :param

    def initialize(param)
      @param = param
      super("param is missing or the value is empty: #{param}")
    end
  end

  # Raised when a Policy or controller is configured in a form
  # StandardAPI doesn't support
  class InvalidConfiguration < StandardAPIError
  end

  # Raised when rendering or describing a model that has no Policy
  class MissingPolicy < StandardAPIError
    attr_reader :model

    def initialize(model)
      @model = model
      super("#{model.name} has no Policy; nest a Policy in its controller or define #{model.name}Policy, subclasses of StandardAPI::Policy")
    end
  end

  class UnpermittedParameters < StandardAPIError
    attr_reader :params

    def initialize(params)
      @params = params
      super("found unpermitted parameter#{'s' if params.size > 1 }: #{params.map { |e| e.inspect }.join(", ")}")
    end
  end
end
