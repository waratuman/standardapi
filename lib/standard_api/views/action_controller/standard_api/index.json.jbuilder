models = @records if !models

json.array! models, partial: 'action_controller/standard_api/model', as: :model, includes: includes
