require 'rails'
require 'action_view'
require 'action_pack'
require 'action_controller'
require 'jbuilder'
require 'jbuilder/railtie'
require 'active_record/filter'
require 'active_record/sort'

if !ActionView::Template.registered_template_handler(:jbuilder)
  ActionView::Template.register_template_handler :jbuilder, JbuilderHandler
end

require 'standard_api/includes'

module StandardAPI

  def self.included(klass)
    klass.hide_action :current_mask
    klass.helper_method :includes, :orders
    klass.prepend_view_path(File.join(File.dirname(__FILE__), 'standard_api', 'views'))
  end

  def index
    @records = resources.limit(params[:limit]).offset(params[:offset]).sort(orders)
    instance_variable_set("@#{model.model_name.plural}", @records)
  end

  def calculate
    @calculations = resources.reorder(nil).pluck(*calculate_selects).map do |c|
      if c.is_a?(Array)
        c.map { |v| v.is_a?(BigDecimal) ? v.to_f : v }
      else
        c.is_a?(BigDecimal) ? c.to_f : c
      end
    end
    render json: @calculations
  end

  def show
    @record = resources.find(params[:id])
    instance_variable_set("@#{model.model_name.singular}", @record)
  end

  def create
    @record = model.new(model_params)
    instance_variable_set("@#{model.model_name.singular}", @record)
    render :show, status: @record.save ? :created : :bad_request
  end

  def update
    @record = resources.find(params[:id])
    instance_variable_set("@#{model.model_name.singular}", @record)
    render :show, status: @record.update_attributes(model_params) ? :ok : :bad_request
  end

  def destroy
    resources.find(params[:id]).destroy!
    render nothing: true, status: :no_content
  end

  # Override if you want to support masking
  def current_mask
    @current_mask ||= {}
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

  def includes
    @includes ||= StandardAPI::Includes.normalize(params[:include] || [])
  end

  # TODO: sanitize orders
  def orders
    normalized_order(params[:order])
  end

  def normalized_order(orderings)
    return nil if orderings.nil?

    orderings = Array(orderings)

    orderings.map! do |order|
      if order.is_a?(Symbol) || order.is_a?(String)
        order = order.to_s
        if order.index(".")
          relation, column = order.split('.').map(&:to_sym)
          { relation => [column] }
        else
          order.to_sym
        end
      elsif order.is_a?(Hash)
        normalized_order = {}
        order.each do |key, value|
          key = key.to_s

          if key.index(".")
            relation, column = key.split('.').map(&:to_sym)
            normalized_order[relation] ||= []
            normalized_order[relation] << { column => value }
          elsif value.is_a?(Hash) && value.keys.first.to_s != 'desc' && value.keys.first.to_s != 'asc'
            normalized_order[key.to_sym] ||= []
            normalized_order[key.to_sym] << value
          else
            normalized_order[key.to_sym] = value
          end
        end
        normalized_order
      end
    end

    orderings
  end

  # Used in #calculate
  # [{ count: :id }]
  # [{ count: '*' }]
  # [{ count: '*', maximum: :id, minimum: :id }]
  # [{ count: '*' }, { maximum: :id }, { minimum: :id }]
  # TODO: Sanitize (normalize_select_params(params[:select], model))
  def calculate_selects
    return @selects if defined?(@selects)

    functions = ['minimum', 'maximum', 'average', 'sum', 'count']
    @selects = []
    Array(params[:select]).each do |select|
      select.each do |func, column|
        column = column == '*' ? Arel.star : column.to_sym
        if functions.include?(func.to_s.downcase)
          @selects << (model.arel_table[column.to_sym].send(func).to_sql)
        end
      end
    end

    @selects
  end

end