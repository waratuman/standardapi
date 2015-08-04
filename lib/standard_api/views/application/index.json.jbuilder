models = @records if !models

json.array! models, partial: 'application/model', as: :model, includes: includes
