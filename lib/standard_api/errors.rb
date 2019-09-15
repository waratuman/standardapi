module StandardAPI
  class StandardAPIError < StandardError
  end

  class UnpermittedParameters < StandardAPIError
    attr_reader :params

    def initialize(params)
      @params = params
      super("found unpermitted parameter#{'s' if params.size > 1 }: #{params.map { |e| e.inspect }.join(", ")}")
    end
  end
end
