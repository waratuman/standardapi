module KeywordACL

  def attributes
    [ "transaxtion" ]
  end

  def filter(model_params, id: nil, allow_id: nil)
    filter_model_params(model_params,
      Keyword,
      id: id,
      allow_id: allow_id
    ).tap do |params|
      if params[:transaction]
        params[:transaxtion] = params.delete(:transaction)
      end
    end
  end

end
