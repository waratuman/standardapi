module StandardAPI
  module Controller
    include StandardAPI::Orders
    include StandardAPI::Includes
    include StandardAPI::Wheres

    # Keys that may appear alongside association names in an `include` and that
    # scope the query rather than name a relation.
    RESERVED_INCLUDE_KEYS = ['limit', 'offset', 'order', 'when', 'where', 'distinct', 'distinct_on'].freeze

    delegate :preloadables, :model_partial,
      :read_schema_for, :write_schema_for, :query_schema_for, to: :helpers

    def self.included(klass)
      klass.include StandardAPI::Policies
      klass.helper_method :includes, :record_policy, :policy_varies?,
        :masked?, :mask_affect?, :orders, :model, :models, :resource_limit,
        :default_limit, :mask
      klass.before_action :set_standardapi_headers
      klass.before_action :includes, only: [:create, :update, :create_resource]

      klass.rescue_from StandardAPI::ParameterMissing, with: :bad_request
      klass.rescue_from StandardAPI::UnpermittedParameters, with: :bad_request
      klass.rescue_from ::ActiveRecord::Sort::InvalidSort, with: :bad_request
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

    # JSON Schema of the record #show renders, with the +include+ param. Not
    # found for a controller without a model, which has nothing to describe.
    def read_schema
      return head :not_found if model.nil?

      render json: read_schema_for(model, includes)
    end

    # JSON Schema of the params #create and #update accept
    def write_schema
      return head :not_found if model.nil?

      render json: write_schema_for(model)
    end

    # JSON Schema of the params #index and #calculate accept
    def query_schema
      return head :not_found if model.nil?

      render json: query_schema_for(model)
    end

    def index
      records = preloadables(resources.limit(limit).offset(params[:offset]).sort(orders), includes)
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
      @calculations = Hash[@calculations] if @calculations[0].is_a?(Array) && group_by.any?

      render json: @calculations
    end

    def show
      instance_variable_set("@#{model.model_name.singular}", resource)
    end

    def new
      instance_variable_set("@#{model.model_name.singular}", model.new) if model
    end

    def create
      resource.assign_attributes(model_params)
      instance_variable_set("@#{model.model_name.singular}", resource)

      if resource.save
        headers['Affected-Rows'] = 1
        if request.format == :html
          redirect_to url_for(
            controller: resource.class.base_class.model_name.collection,
            action: 'show',
            id: resource.id,
            only_path: true
          )
        else
          render :show, status: :created
        end
      else
        headers['Affected-Rows'] = 0
        if request.format == :html
          render :new, status: :bad_request
        else
          render :show, status: :bad_request
        end
      end
    end

    def update
      instance_variable_set("@#{model.model_name.singular}", resource)

      if resource.update(model_params)
        headers['Affected-Rows'] = 1
        if request.format == :html
          redirect_to url_for(
            controller: resource.class.base_class.model_name.collection,
            action: 'show',
            id: resource.id,
            only_path: true
          )
        else
          render :show, status: :ok
        end
      else
        headers['Affected-Rows'] = 0
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

      headers['Affected-Rows'] = records.size
      head :no_content
    end

    def remove_resource
      resource = resources.find(params[:id])
      association = resource.association(params[:relationship])

      result = case association
      when ::ActiveRecord::Associations::CollectionAssociation
        association.delete(association.klass.find(params[:resource_id]))
      when ::ActiveRecord::Associations::SingularAssociation
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
      when ::ActiveRecord::Associations::CollectionAssociation
        association.concat(subresource)
      when ::ActiveRecord::Associations::SingularAssociation
        resource.update(params[:relationship] => subresource)
      end
      head result ? :created : :bad_request
    rescue ::ActiveRecord::RecordNotUnique
      render json: {errors: [
        "Relationship between #{resource.class.name} and #{subresource.class.name} violates unique constraints"
      ]}, status: :bad_request
    end

    def create_resource
      resource = resources.find(params[:id])
      association = resource.association(params[:relationship])
      subresource = association.klass.new
      subresource.assign_attributes(filter_model_params(subresource, params[model_name(association.klass)]))

      result = case association
      when ::ActiveRecord::Associations::CollectionAssociation
        association.concat(subresource)
      when ::ActiveRecord::Associations::SingularAssociation
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

    # The key +model+'s params are sent under, and its Policy is registered
    # under
    def model_name(model)
      if model.model_name.singular.starts_with?('habtm_')
        model.reflect_on_all_associations.map { |a| a.klass.base_class.model_name.singular }.sort.join('_')
      else
        model.model_name.singular
      end
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
      # Several controllers can serve one model; schema.json lists it once.
      @models.uniq!
      @models
    end

    def model_params
      return @model_params if instance_variable_defined?(:@model_params)
      @model_params = filter_model_params(resource, params[model_name(model)])
    end

    # The params of +resource+ its Policy, or +policy+ in its place, makes
    # writable (Policy::Record#writable), and of the associations it makes
    # writable (Policy::Record#writable_associations): the nested records'
    # own, their ids, or the foreign key. What it assigns
    # (Policy::Record#assigned_attributes) overrides the params, and then its
    # filters run on them (Policy::Record#filter_params).
    def filter_model_params(resource, model_params, allow_id: nil, policy: nil)
      write_policy = record_policy(resource, policy)
      if !model_params
        params = write_policy.filter_params(ActionController::Parameters.new(write_policy.assigned_attributes))
        # The server set all of it, so it's permitted
        return params.empty? ? params : params.permit!
      end

      permitted_params = allow_id ? model_params.permit(write_policy.writable, :id) : model_params.permit(write_policy.writable)

      # A json column is permitted as an object, which strong parameters
      # don't let be null, so a null sent for it is kept here
      write_policy.writable.each do |entry|
        next if !entry.is_a?(Hash)
        entry.each do |name, permit|
          next if permit != {} || !model_params.key?(name) || !model_params[name].nil?
          permitted_params[name] = nil if Policy.json_attribute?(write_policy.model, name)
        end
      end

      write_policy.writable_associations.each do |relation|
        association = resource.association(relation.to_sym)
        attributes_key = association.reflection.name.to_s
        nested_policy = write_policy.writable_policy(relation)
        if model_params.has_key?(attributes_key)
          if model_params[attributes_key].nil?
            permitted_params[attributes_key] = nil
          elsif model_params[attributes_key].is_a?(Array) && model_params[attributes_key].all? { |a| a.keys.map(&:to_sym) == [:id] }
            permitted_params["#{association.reflection.name.to_s.singularize}_ids"] = model_params[attributes_key].map{|a| a['id']}
          else
            permitted_params[attributes_key] = if model_params[attributes_key].is_a?(Array)
              models = association.klass.find(model_params[attributes_key].map { |i| i['id'] }.compact)
              model_params[attributes_key].map { |i|
                nested_record = i['id'] ? models.find { |r| r.id == i['id'] } : association.klass.new
                i_params = filter_model_params(nested_record, i, allow_id: true, policy: nested_policy)
                nested_record.assign_attributes(i_params)
                nested_record
              }
            else
              nested_record = model_params[attributes_key]['id'] ? association.klass.find(model_params[attributes_key]['id']) : association.klass.new
              i_params = filter_model_params(nested_record, model_params[attributes_key], allow_id: true, policy: nested_policy)
              nested_record.assign_attributes(i_params)
              nested_record
            end
          end
        elsif association.collection? && model_params.has_key?("#{association.reflection.name.to_s.singularize}_ids")
          permitted_params["#{association.reflection.name.to_s.singularize}_ids"] = model_params["#{association.reflection.name.to_s.singularize}_ids"]
        elsif model_params.has_key?(association.reflection.foreign_key)
          permitted_params[association.reflection.foreign_key] = model_params[association.reflection.foreign_key]
          permitted_params[association.reflection.foreign_type] = model_params[association.reflection.foreign_type] if association.reflection.polymorphic?
        end
      end
      # The nested records were filtered by their own Policy
      permitted_params.permit!

      write_policy.assigned_attributes.each { |name, value| permitted_params[name] = value }
      write_policy.filter_params(permitted_params)
    end

    # True when what +klass+ renders could differ by requester: its Policy
    # could (Policy.varies_by_requester?), or that of any model +includes+
    # reach through it. A record loaded as +klass+ can be of one of its STI
    # subclasses, which renders with its own Policy, so theirs count as well
    # (#rendered_models).
    #
    # This is deliberately a "could apply" test rather than "does apply": it
    # answers the question without a record in hand, which is what the view
    # caching guards need. Policies#record_policy is resolved per record and
    # may depend on the current user, but the fragment cache keys in the views
    # are built from record timestamps only. Caching a fragment whose contents
    # depend on the requester would let one requester's response be served to
    # another, so the views use this to skip caching whenever it could.
    def policy_varies?(klass, includes = {})
      @policy_varies ||= {}
      varies = @policy_varies.fetch(klass) do
        @policy_varies[klass] = rendered_models(klass).any? { |k| model_policy(k)&.class&.varies_by_requester? }
      end
      return true if varies

      includes.any? do |inc, subinc|
        next false if RESERVED_INCLUDE_KEYS.include?(inc.to_s)

        association = klass.reflect_on_association(inc)
        # A method can return records of any model, which render with their
        # Policy and, for a relation, through #mask, so assume it could vary.
        next true if association.nil?
        # A polymorphic association's class isn't known until a record is
        # loaded, so assume it could vary.
        next true if association.polymorphic?

        policy_varies?(association.klass, subinc.is_a?(Hash) ? subinc : {})
      end
    end

    # The models a record loaded as +klass+ could turn out to be: +klass+ and,
    # with single table inheritance, its subclasses. Which one isn't known
    # until the record is loaded, and a cached fragment never loads it.
    #
    # A subclass is only known once it's loaded, so without eager loading
    # (ie. in development) the app is loaded first, as #models does.
    # Otherwise a fragment rendered before the subclass was first referenced
    # would be cached as though its Policy didn't exist.
    def rendered_models(klass)
      sti = klass.respond_to?(:inheritance_column) && klass.inheritance_column &&
        klass.columns_hash.key?(klass.inheritance_column.to_s)
      return [klass] if !sti

      Rails.application.eager_load! if !Rails.application.config.eager_load
      [klass, *klass.descendants]
    end

    # True when #mask hides rows of +klass+ for this request.
    def masked?(klass)
      mask[klass.table_name.to_sym].present?
    end

    # True when rendering +klass+ with +includes+ depends on the current mask.
    #
    # _record filters every included collection through #mask, so which rows
    # appear inside a fragment varies by requester while the cache key does
    # not. Same problem as #policy_varies?, same fix: don't cache it. The
    # top level is masked in #resources rather than in the view, so a record
    # the mask hides is simply absent from the collection and needs no guard
    # here.
    def mask_affect?(klass, includes)
      includes.any? do |inc, subinc|
        next false if RESERVED_INCLUDE_KEYS.include?(inc.to_s)

        association = klass.reflect_on_association(inc)
        next false if association.nil?
        next true if association.polymorphic?
        next true if association.collection? && masked?(association.klass)

        mask_affect?(association.klass, subinc.is_a?(Hash) ? subinc : {})
      end
    end

    def resources
      query = self.class.model.filter(wheres).filter(mask[self.class.model.table_name.to_sym])

      if params[:distinct_on]
        query = query.distinct_on(params[:distinct_on])
      elsif params[:distinct]
        query = query.distinct
      end

      if params[:join]
        query = query.joins(params[:join].to_sym)
      end

      query = query.group(*group_by) if group_by.any?

      query
    end

    def resource
      return @resource if instance_variable_defined?(:@resource)

      @resource = if action_name == "create"
        model.new
      else
        preloadables(resources, includes).find(params[:id])
      end
    end

    # The associations +attributes+ write through nested attributes, as
    # includes, so #create and #update render what they wrote. +on+ is the
    # action writing them, as the record itself isn't loaded yet, and
    # +policy+ the Policy class they're written with, if not their own.
    def nested_includes(model, attributes, on, policy = nil)
      write_policy = record_policy(model, policy)
      writable = write_policy.writable_associations(on: on)
      includes = {}
      attributes&.each do |key, value|
        association = model.reflect_on_association(key)
        if association && writable.include?(association.name.to_s)
          includes[key] = if value.is_a?(Hash)
            nested_includes(association.klass, value, value['id'] ? :update : :create, write_policy.writable_policy(association.name))
          else
            {}
          end
        end
      end

      includes
    end

    def includes
      @includes ||= if params[:include]
        sanitize_includes(params[:include], model)
      else
        {}
      end

      # What a create or update wrote through nested attributes renders too,
      # where the Policy declares it
      if (action_name == 'create' || action_name == 'update') && model && params.has_key?(model.model_name.singular)
        @includes.reverse_merge!(nested_includes(model, params[model.model_name.singular].to_unsafe_h, action_name.to_sym))
      end

      @includes
    end

    def default_orders
      nil
    end

    # The +where+ param, checked against what the Policy makes filterable. It filters
    # #resources, ie. the controller's model even in the *_resource actions,
    # where #model is the association's model.
    def wheres
      return @wheres if defined?(@wheres)

      @wheres = sanitize_wheres(params['where'], record_policy(self.class.model))
    end

    # The +group_by+ param as columns of the controller's model, which
    # #resources groups by and #calculate selects. Only column names are
    # accepted; a String passed to +group+ would be used as raw SQL.
    def group_by
      return @group_by if defined?(@group_by)

      @group_by = Array.wrap(params[:group_by]).map do |name|
        if !name.is_a?(String) || !self.class.model.columns_hash.has_key?(name)
          raise StandardAPI::UnpermittedParameters.new(["group_by"])
        end

        self.class.model.arel_table[name]
      end
    end

    # The +order+ param, or #default_orders without one, checked against what
    # the Policy makes orderable, then what it declares +required_orders+ that
    # isn't already ordered by
    def orders
      return @orders if defined?(@orders)

      policy = record_policy(model)
      orders = sanitize_orders(params[:order] || default_orders, policy)
      ordered = order_names(orders)
      required = policy.required_orders.reject { |name| ordered.include?(name) }
      @orders = required.empty? ? orders : Array.wrap(orders) + required
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
      @selects.concat(group_by)
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

          if functions.include?(func.to_s.downcase)
            attribute = column == '*' ? Arel.star : (defined?(@model) ? @model : model).arel_table[column.to_sym]
            node = attribute.send(func)
            node.distinct = distinct
            @selects << node
          end
        end
      end

      @selects
    end

  end
end
