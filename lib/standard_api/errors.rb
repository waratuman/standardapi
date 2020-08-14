# frozen_string_literal: true

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

  class UnpermittedParameters < StandardAPIError
    attr_reader :params

    def initialize(params)
      @params = params
      super("found unpermitted parameter#{'s' if params.size > 1 }: #{params.map { |e| e.inspect }.join(", ")}")
    end
  end
end
