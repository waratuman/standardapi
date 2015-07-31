require 'action_pack'

class ActionController::StandardAPI < ActionController::Base

  before_action :set_includes, :set_orders

  def index
    results = resources.limit(params[:limit]).offset(params[:offset]).sort(@orders)
    instance_variable_set("@#{model.model_name.plural}", results)
  end

  def calculate
    selects = normalize_select_params(params[:select], model)

    @calculations = resources.reorder(nil).pluck(*selects).map { |c|
      if c.is_a?(Array)
        c.map { |v| v.is_a?(BigDecimal) ? v.to_f : v }
      else
        c.is_a?(BigDecimal) ? c.to_f : c
      end
    }

    render json: @calculations
  end

  def show
    result = resources.find(params[:id])
    instance_variable_set("@#{model.model_name.singular}", result)
  end

  def create
    result = model.new(model_params)
    instance_variable_set("@#{model.model_name.singular}", result)
    render :show, status: result.save ? :created : :bad_request
  end

  def update
    result = resources.find(params[:id])
    instance_variable_set("@#{model.model_name.singular}", result)
    render :show, status: result.update_attributes(model_params) ? :ok : :bad_request
  end

  def destroy
    resources.find(params[:id]).destroy!
    render nothing: true, status: :no_content
  end

  private

  def model
    return @model if defined?(@model)
    @model = self.class.name.sub(/Controller\z/, '').singularize.camelize.constantize
  end

  def model_params
    params.require(model.model_name.singular).permit(self.send("#{model.model_name.singular}_params"))
  end

  def model_includes
    self.send "#{model.model_name.singular}_includes"
  end

  def model_orders
    self.send "#{model.model_name.singular}_orders"
  end

  def resources
    model.filter(params[:where]).where(current_mask[model.table_name])
  end

  def set_includes
    @includes = sanitize_includes(params[:include], model_includes)
  end

  def set_orders
    @orders = if params[:where].try(:[], :query)
      nil
    else
      sanitize_order(params[:order], model_orders)
    end
  end

end