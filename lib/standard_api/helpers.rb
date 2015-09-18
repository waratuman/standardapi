module StandardAPI
  module Helpers

    def model_partial(record)
      if lookup_context.exists?(record.model_name.element, controller_name, true)
        [record.model_name.plural, record.model_name.element].join('/')
      else
        'application/record'
      end
    end

  end
end