module StandardAPI
  module Controller

    delegate :preloadables, :model_partial, to: :helpers

    def self.included(klass)
      klass.helper_method :includes, :orders, :model, :models, :resource_limit,
        :default_limit
      klass.before_action :set_standardapi_headers
      klass.before_action :includes, except: [:destroy, :add_resource, :remove_resource]
      klass.rescue_from StandardAPI::ParameterMissing, with: :bad_request
      klass.rescue_from StandardAPI::UnpermittedParameters, with: :bad_request
      klass.append_view_path(File.join(File.dirname(__FILE__), 'views'))
      klass.extend(ClassMethods)
    end

    def tables
      Rails.application.eager_load! if !Rails.application.config.eager_load

      tables = ApplicationController.descendants
      tables.select! { |c| c.ancestors.include?(self.class) && c != self.class }
      tables.map!(&:model).compact!
      tables.map!(&:table_name)
      render json: tables
    end

    if Rails.env == 'development'
      def schema
        Rails.application.eager_load! if !Rails.application.config.eager_load
      end
    end

    def index
      records = preloadables(resources.limit(limit).offset(params[:offset]).sort(orders), includes, true)
      instance_variable_set("@#{model.model_name.plural}", records)
    end

    def calculate
      @calculations = resources.reorder(nil).pluck(*calculate_selects).map do |c|
        if c.is_a?(Array)
          c.map { |v| v.is_a?(BigDecimal) ? v.to_f : v }
        else
          c.is_a?(BigDecimal) ? c.to_f : c
        end
      end
      @calculations = Hash[@calculations] if @calculations[0].is_a?(Array) && params[:group_by]

      render json: @calculations
    end

    def show
      record = preloadables(resources, includes).find(params[:id])
      instance_variable_set("@#{model.model_name.singular}", record)
    end

    def new
      instance_variable_set("@#{model.model_name.singular}", model.new) if model
    end

    def create
      record = model.new(model_params)
      instance_variable_set("@#{model.model_name.singular}", record)

      if record.save
        if request.format == :html
          redirect_to url_for(
            controller: record.class.base_class.model_name.collection,
            action: 'show',
            id: record.id,
            only_path: true
          )
        else
          render :show, status: :created
        end
      else
        if request.format == :html
          render :new, status: :bad_request
        else
          render :show, status: :bad_request
        end
      end
    end

    def update
      record = resources.find(params[:id])
      instance_variable_set("@#{model.model_name.singular}", record)

      if record.update(model_params)
        if request.format == :html
          redirect_to url_for(
            controller: record.class.base_class.model_name.collection,
            action: 'show',
            id: record.id,
            only_path: true
          )
        else
          render :show, status: :ok
        end
      else
        if request.format == :html
          render :edit, status: :bad_request
        else
          render :show, status: :bad_request
        end
      end
    end

    def destroy
      records = resources.find(params[:id].split(','))
      model.transaction { records.each(&:destroy!) }

      head :no_content
    end

    def remove_resource
      resource = resources.find(params[:id])
      association = resource.association(params[:relationship])

      result = case association
      when ActiveRecord::Associations::CollectionAssociation
        association.delete(association.klass.find(params[:resource_id]))
      when ActiveRecord::Associations::SingularAssociation
        if resource.send(params[:relationship])&.id&.to_s == params[:resource_id]
          resource.update(params[:relationship] => nil)
        end
      end
      head result ? :no_content : :not_found
    end

    def add_resource
      resource = resources.find(params[:id])
      association = resource.association(params[:relationship])
      subresource = association.klass.find(params[:resource_id])

      result = case association
      when ActiveRecord::Associations::CollectionAssociation
        association.concat(subresource)
      when ActiveRecord::Associations::SingularAssociation
        resource.update(params[:relationship] => subresource)
      end
      head result ? :created : :bad_request
    rescue ActiveRecord::RecordNotUnique
      render json: {errors: [
        "Relationship between #{resource.class.name} and #{subresource.class.name} violates unique constraints"
      ]}, status: :bad_request
    end
    
    def create_resource
      resource = resources.find(params[:id])
      association = resource.association(params[:relationship])
    
      subresource_params = if self.respond_to?("filter_#{model_name(association.klass)}_params", true)
        self.send("filter_#{model_name(association.klass)}_params", params[model_name(association.klass)], id: params[:id])
      elsif self.respond_to?("#{association.klass.model_name.singular}_params", true)
        params.require(association.klass.model_name.singular).permit(self.send("#{association.klass.model_name.singular}_params"))
      elsif self.respond_to?("filter_model_params", true)
        filter_model_params(params[model_name(association.klass)], association.klass.base_class)
      else
        ActionController::Parameters.new
      end
    
      subresource = association.klass.new(subresource_params)
    
      result = case association
      when ActiveRecord::Associations::CollectionAssociation
        association.concat(subresource)
      when ActiveRecord::Associations::SingularAssociation
        resource.update(params[:relationship] => subresource)
      end

      partial = model_partial(subresource)
      partial_record_name = partial.split('/').last.to_sym
      if result
        render partial: partial, locals: {partial_record_name => subresource}, status: :created
      else
        render partial: partial, locals: {partial_record_name => subresource}, status: :bad_request
      end
    end

    def mask
      @mask ||= Hash.new do |hash, key|
        hash[key] = mask_for(key)
      end
    end
    
    # Override if you want to support masking
    def mask_for(table_name)
      # case table_name
      # when 'accounts'
      # end
    end

    module ClassMethods

      def model
        return @model if defined?(@model)
        @model = name.sub(/Controller\z/, '').singularize.camelize.safe_constantize
      end

    end

    private

    def bad_request(exception)
      render body: exception.to_s, status: :bad_request
    end

    def set_standardapi_headers
      headers['StandardAPI-Version'] = StandardAPI::VERSION
    end

    def model
      if action_name&.end_with?('_resource')
        self.class.model.reflect_on_association(params[:relationship]).klass
      else
        self.class.model
      end
    end

    def models
      return @models if defined?(@models)
      Rails.application.eager_load! if !Rails.application.config.eager_load

      @models = ApplicationController.descendants
      @models.select! { |c| c.ancestors.include?(self.class) && c != self.class }
      @models.map!(&:model).compact!
    end

    def model_includes
      if self.respond_to?("#{model.model_name.singular}_includes", true)
        self.send("#{model.model_name.singular}_includes")
      else
        []
      end
    end

    def model_orders
      if self.respond_to?("#{model.model_name.singular}_orders", true)
        self.send("#{model.model_name.singular}_orders")
      else
        []
      end
    end

    def model_params
      if self.respond_to?("#{model.model_name.singular}_params", true)
        params.require(model.model_name.singular).permit(self.send("#{model.model_name.singular}_params"))
      else
        ActionController::Parameters.new
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
      query = self.class.model.filter(params['where']).filter(mask[self.class.model.table_name.to_sym])

      if params[:distinct_on]
        query = query.distinct_on(params[:distinct_on])
      elsif params[:distinct]
        query = query.distinct
      end

      if params[:join]
        query = query.joins(params[:join].to_sym)
      end

      if params[:group_by]
        query = query.group(params[:group_by])
      end

      query
    end
    
    def nested_includes(model, attributes)
      includes = {}
      attributes&.each do |key, value|
        if association = model.reflect_on_association(key)
          includes[key] = nested_includes(association.klass, value)
        end
      end
      includes
    end

    def includes
      @includes ||= if params[:include]
        StandardAPI::Includes.sanitize(params[:include], model_includes)
      else
        {}
      end
      
      if (action_name == 'create' || action_name == 'update') && model && params.has_key?(model.model_name.singular)
        @includes.reverse_merge!(nested_includes(model, params[model.model_name.singular].to_unsafe_h))
      end
      
      @includes
    end

    def required_orders
      []
    end

    def default_orders
      nil
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

      @orders ||= StandardAPI::Orders.sanitize(params[:order] || default_orders, model_orders | required_orders)
    end

    def excludes
      @excludes ||= model_excludes
    end

    # The maximum number of results returned by #index
    def resource_limit
      1000
    end

    # The default limit if params[:limit] is no specified in a request.
    # If this value should be less than the `resource_limit`. Return `nil` if
    # you want the limit param to be required.
    def default_limit
      nil
    end

    def limit
      if resource_limit
        limit = params.permit(:limit)[:limit]&.to_i || default_limit

        if !limit
          raise StandardAPI::ParameterMissing.new(:limit)
        elsif limit > resource_limit
          raise StandardAPI::UnpermittedParameters.new([:limit, limit])
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
      @selects << params[:group_by] if params[:group_by]
      Array(params[:select]).each do |select|
        select.each do |func, value|
          distinct = false

          column = case value
          when ActionController::Parameters
            # TODO: Add support for other aggregate expressions
            # https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES
            distinct = !value[:distinct].nil?
            value[:distinct]
          else
            value
          end

          if (parts = column.split(".")).length > 1
            @model = parts[0].singularize.camelize.constantize
            column = parts[1]
          end

          column = column == '*' ? Arel.star : column.to_sym
          if functions.include?(func.to_s.downcase)
            node = (defined?(@model) ? @model : model).arel_table[column].send(func)
            node.distinct = distinct
            @selects << node
          end
        end
      end

      @selects
    end

  end
end
