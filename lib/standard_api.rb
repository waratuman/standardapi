require 'rails'
require 'action_view'
require 'action_pack'
require 'action_controller'
require 'jbuilder'
require 'jbuilder/railtie'
require 'active_record/filter'
require 'active_record/sort'
require 'active_support/core_ext/hash/indifferent_access'

if !ActionView::Template.registered_template_handler(:jbuilder)
  ActionView::Template.register_template_handler :jbuilder, JbuilderHandler
end

require 'standard_api/orders'
require 'standard_api/includes'

module StandardAPI

  def self.included(klass)
    klass.hide_action :current_mask
    klass.helper_method :includes, :orders, :model
    klass.append_view_path(File.join(File.dirname(__FILE__), 'standard_api', 'views'))
    klass.extend(ClassMethods)
  end
  
  def ping
    render :text => 'pong'
  end

  def tables
    controllers = Dir[Rails.root.join('app/controllers/*_controller.rb')].map{ |path| path.match(/(\w+)_controller.rb/)[1].camelize+"Controller" }.map(&:safe_constantize)
    controllers.select! { |c| c.ancestors.include?(self.class) && c != self.class }
    controllers.map!(&:model).compact!.map!(&:table_name)
    
    render json: controllers
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

  module ClassMethods
    
    def model
      return @model if defined?(@model)
      @model = name.sub(/Controller\z/, '').singularize.camelize.safe_constantize
    end

  end
  
  private

  def model
    self.class.model
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

  def excludes_for(klass)
    if defined?(ApplicationHelper) && ApplicationHelper.instance_methods.include?(:excludes)
       excludes = Class.new.send(:include, ApplicationHelper).new.excludes.with_indifferent_access
       excludes.try(:[], klass.model_name.singular) || []
    else
      []
    end
  end

  def model_excludes
    excludes_for(model)
  end

  def resources
    model.filter(params[:where]).where(current_mask[model.table_name])
  end

  def includes
    @includes ||= StandardAPI::Includes.normalize(params[:include])
  end

  def orders
    @orders ||= StandardAPI::Orders.sanitize(params[:order], model_orders)
  end

  def excludes
    @excludes ||= model_excludes
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
          @selects << (model.arel_table[column].send(func).to_sql)
        end
      end
    end

    @selects
  end

end
