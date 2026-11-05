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

  # Raised when an ACL or controller uses a form StandardAPI no longer supports
  class InvalidConfiguration < StandardAPIError
  end

  # Raised when rendering or describing a model that has no Schema
  class MissingSchema < StandardAPIError
    attr_reader :model

    def initialize(model)
      @model = model
      super("#{model.name} has no Schema; nest a Schema in its controller or define #{model.name}Schema, subclasses of StandardAPI::Schema")
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
