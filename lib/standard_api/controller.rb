module StandardAPI
  module Controller

    def self.included(klass)
      klass.helper_method :includes, :orders, :model
      klass.append_view_path(File.join(File.dirname(__FILE__), 'views'))
      klass.before_action(:extract_params)
      klass.extend(ClassMethods)
    end
    
    def extract_params
      if params[:m]
        MessagePack.unpack(URI.decode(params[:m])).each do |key, value|
          params[key] = value
        end
      end
    end
  
    def ping
      render plain: 'pong'
    end

    def tables
      controllers = Dir[Rails.root.join('app/controllers/*_controller.rb')].map{ |path| path.match(/(\w+)_controller.rb/)[1].camelize+"Controller" }.map(&:safe_constantize)
      controllers.select! { |c| c.ancestors.include?(self.class) && c != self.class }
      controllers.map!(&:model).compact!
      controllers.map!(&:table_name)
    
      render json: controllers
    end  

    def index
      instance_variable_set("@#{model.model_name.plural}", resources.limit(params[:limit]).offset(params[:offset]).sort(orders))
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
        render :show, status: :bad_request
      end
    end

    def update
      instance_variable_set("@#{model.model_name.singular}", resources.find(params[:id]))
      render :show, status: instance_variable_get("@#{model.model_name.singular}").update_attributes(model_params) ? :ok : :bad_request
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
end
