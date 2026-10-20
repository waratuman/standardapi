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

  class UnpermittedParameters < StandardAPIError
    attr_reader :params

    def initialize(params)
      @params = params
      super("found unpermitted parameter#{'s' if params.size > 1 }: #{params.map { |e| e.inspect }.join(", ")}")
    end
  end
end
