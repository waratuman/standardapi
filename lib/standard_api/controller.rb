module StandardAPI
  module Controller

    def self.included(klass)
      klass.helper_method :includes, :orders, :model, :resource_limit
      klass.before_action :set_standardapi_headers
      klass.append_view_path(File.join(File.dirname(__FILE__), 'views'))
      klass.extend(ClassMethods)
    end

    def tables
      controllers = ApplicationController.descendants# Dir[Rails.root.join('app/controllers/*_controller.rb')].map{ |path| path.match(/(\w+)_controller.rb/)[1].camelize+"Controller" }.map(&:safe_constantize)
      controllers.select! { |c| c.ancestors.include?(self.class) && c != self.class }
      controllers.map!(&:model).compact!
      controllers.map!(&:table_name)
      render json: controllers
    end

    def index
      instance_variable_set("@#{model.model_name.plural}", resources.limit(limit).offset(params[:offset]).sort(orders))
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
      instance_variable_set("@#{model.model_name.singular}", resources.find(params[:id]))
    end

    def new
      instance_variable_set("@#{model.model_name.singular}", model.new) if model
    end

    def create
      record = model.new(model_params)
      instance_variable_set("@#{model.model_name.singular}", record)
      
      if record.save
        if request.format == :html
          redirect_to record
        else
          render :show, status: :created
        end
      else
        if request.format == :html
          render :edit, status: :bad_request
        else
          render :show, status: :bad_request
        end
      end
    end

    def update
      record = resources.find(params[:id])
      instance_variable_set("@#{model.model_name.singular}", record)

      if record.update_attributes(model_params)
        if request.format == :html
          redirect_to record
        else
          render :show, status: :ok
        end
      else
        render :show, status: :bad_request
      end
    end

    def destroy
      resources.find(params[:id]).destroy!
      head :no_content
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

      def model_includes
        if self.respond_to?("#{model.model_name.singular}_includes", true)
          self.send "#{model.model_name.singular}_includes"
        else
          []
        end
      end

      def model_orders
        if self.respond_to?("#{model.model_name.singular}_orders", true)
          self.send "#{model.model_name.singular}_orders"
        else
          []
        end
      end

    end

    private

    def set_standardapi_headers
      headers['StandardAPI-Version'] = StandardAPI::VERSION
    end

    def model
      self.class.model
    end

    def model_includes
      self.class.model_includes
    end

    def model_orders
      self.class.model_orders
    end

    def model_params
      if self.respond_to?("#{model.model_name.singular}_params", true)
        params.require(model.model_name.singular).permit(self.send("#{model.model_name.singular}_params"))
      else
        []
      end
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
      query = model.filter(params[:where]).filter(current_mask[model.table_name])
      
      if params[:distinct_on]
        query.distinct_on(params[:distinct_on])
      elsif params[:distinct]
        query.distinct
      else
        query
      end
    end

    def includes
      @includes ||= StandardAPI::Includes.normalize(params[:include])
    end
    
    def required_orders
      []
    end

    def orders
      exluded_required_orders = required_orders.map(&:to_s)
      
      case params[:order]
      when Hash, ActionController::Parameters
        exluded_required_orders -= params[:order].keys.map(&:to_s)
      when Array
        params[:order].flatten.each do |v|
          case v
          when Hash, ActionController::Parameters
            exluded_required_orders -= v.keys.map(&:to_s)
          when String
            exluded_required_orders.delete(v)
          end
        end
      when String
        exluded_required_orders.delete(params[:order])
      end
      
      if !exluded_required_orders.empty?
        params[:order] = exluded_required_orders.unshift(params[:order])
      end
      
      @orders ||= StandardAPI::Orders.sanitize(params[:order], model_orders | required_orders)
    end

    def excludes
      @excludes ||= model_excludes
    end

    # The maximum number of results returned by #index
    def resource_limit
      1000
    end

    def limit
      if resource_limit
        limit = params.require(:limit).to_i

        if limit > resource_limit
          raise ActionController::UnpermittedParameters.new([:limit, limit])
        end

        limit
      else
        params.permit(:limit)[:limit]
      end
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
end
