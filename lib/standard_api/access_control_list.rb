module StandardAPI
  module AccessControlList

    def self.traverse(path, prefix: nil, &block)
      path.children.each do |child|
        if child.file? && child.basename('.rb').to_s.ends_with?('_acl')
          block.call([prefix, child.basename('.rb').to_s].compact.join('/'))
        elsif child.directory?
          traverse(child, prefix: [prefix, child.basename.to_s].compact.join('/'), &block)
        end
      end
    end

    # The methods an ACL may define, and the name each is renamed to given the
    # model's prefix.
    METHODS = {
      attributes: '%s_attributes',
      orders: '%s_orders',
      includes: '%s_includes',
      excludes: '%s_excludes',
      nested: 'nested_%s_attributes',
      filter: 'filter_%s_params'
    }.freeze

    def self.included(application_controller)
      base_controllers[application_controller.name || application_controller] = application_controller

      acl_dir = Rails.application.root.join('app', 'controllers', 'acl')
      return if !acl_dir.exist?

      traverse(acl_dir) do |child|
        include_acl(application_controller, child.classify.constantize, child.delete_suffix('_acl').gsub('/', '_'))
      end
    end

    # Controllers that include StandardAPI::AccessControlList, keyed by name so
    # a reloaded class replaces the stale one.
    def self.base_controllers
      @base_controllers ||= {}
    end

    # Include the +ACL+ module nested in any controller below a base controller
    # into that base controller, as #included does for app/controllers/acl.
    # Controllers must already be loaded for their ACL to be found, so the
    # Railtie calls this once they are, at boot and after each reload.
    def self.load!
      base_controllers.each_value do |base|
        [base, *base.descendants].each do |controller|
          next if !controller.const_defined?(:ACL, false)

          acl = controller.const_get(:ACL, false)
          model = controller.model
          raise ArgumentError, "#{acl} is defined but #{controller} has no model" if !model

          include_acl(base, acl, model_name(model), controller: controller)
        end
      end
    end

    # Rename the methods of +acl+ in place under +prefix+, make them private so
    # they aren't routable, and include +acl+ into +base+. A module already
    # renamed or included is skipped, so this is safe to repeat. Methods
    # outside METHODS are rejected rather than silently dropped, as is a name
    # +base+ already gets from somewhere else. When the ACL is nested in
    # +controller+, a method the controller defines under the renamed name
    # would shadow it, so that is rejected too.
    def self.include_acl(base, acl, prefix, controller: nil)
      renames = METHODS.to_h { |m, format| [m, (format % prefix).to_sym] }

      (acl.instance_methods(false) + acl.private_instance_methods(false)).each do |m|
        next if renames.value?(m)
        if !renames.key?(m)
          raise ArgumentError, "#{acl}##{m} is not an ACL method (allowed: #{METHODS.keys.join(', ')})"
        end

        acl.send(:alias_method, renames[m], m)
        acl.send(:remove_method, m)
        acl.send(:private, renames[m])
      end

      return if base.include?(acl)

      (acl.instance_methods(false) + acl.private_instance_methods(false)).each do |name|
        [base, controller].compact.uniq.each do |klass|
          next if !klass.method_defined?(name) && !klass.private_method_defined?(name)

          raise ArgumentError, "#{name} is defined by both #{klass.instance_method(name).owner} and #{acl}"
        end
      end

      base.include(acl)
    end

    def self.model_name(model)
      if model.model_name.singular.starts_with?('habtm_')
        model.reflect_on_all_associations.map { |a| a.klass.base_class.model_name.singular }.sort.join('_')
      else
        model.model_name.singular
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
      return @model_params if instance_variable_defined?(:@model_params)
      @model_params = if self.respond_to?("filter_#{model_name(model)}_params", true)
        self.send("filter_#{model_name(model)}_params", resource, params[model_name(model)], id: params[:id])
      else
        filter_model_params(resource, params[model_name(model)])
      end
    end

    # Resolve the ACL-permitted attribute list for +model+, optionally scoped to
    # a specific +record+. ACL +attributes+ methods may accept a record so they
    # can make per-record decisions; schema rendering has no record and passes
    # +nil+. A zero-arity +attributes+ definition is still supported but
    # deprecated. Returns +nil+ when no ACL +attributes+ method is defined.
    def model_attributes(model, record = nil)
      method_name = "#{model_name(model)}_attributes"
      return nil if !self.respond_to?(method_name, true)

      if self.method(method_name).arity == 0
        logger.warn <<~NOTE.strip_heredoc
          DEPRECATION WARNING: #{ model.name }ACL#attributes() has been deprecated, use #{ model.name }ACL#attributes(record = nil) instead
        NOTE
        self.send(method_name)
      else
        self.send(method_name, record)
      end
    end

    def filter_model_params(resource, model_params, id: nil, allow_id: nil)
      permits = model_attributes(resource.class, resource) if model_params
      permitted_params = if permits
        allow_id ? model_params.permit(permits, :id) : model_params.permit(permits)
      else
        ActionController::Parameters.new
      end

      if self.respond_to?("nested_#{model_name(resource.class)}_attributes", true)
        self.send("nested_#{model_name(resource.class)}_attributes").each do |relation|
          association = resource.association(relation)
          attributes_key = association.reflection.name.to_s
          if model_params.has_key?(attributes_key)
            filter_method = "filter_#{association.klass.base_class.model_name.singular}_params"
            if model_params[attributes_key].nil?
              permitted_params[attributes_key] = nil
            elsif model_params[attributes_key].is_a?(Array) && model_params[attributes_key].all? { |a| a.keys.map(&:to_sym) == [:id] }
              permitted_params["#{association.reflection.name.to_s.singularize}_ids"] = model_params[attributes_key].map{|a| a['id']}
            elsif self.respond_to?(filter_method, true)
              permitted_params[attributes_key] = if model_params[attributes_key].is_a?(Array)
                models = association.klass.find(model_params[attributes_key].map { |i| i['id'] }.compact)
                model_params[attributes_key].map { |i|
                  r = if i['id']
                    models.find { |r| r.id == i['id'] }
                  else
                    association.klass.new
                  end
                  i_params = self.send(filter_method, r, i, allow_id: true)
                  r.assign_attributes(i_params)
                  r
                }
              else
                r = if id = model_params[attributes_key]['id']
                  association.klass.find(id)
                else
                  association.klass.new()
                end
                i_params = self.send(filter_method, r, model_params[attributes_key], allow_id: true)
                r.assign_attributes(i_params)
                r
              end
            else
              permitted_params[attributes_key] = if model_params[attributes_key].is_a?(Array)
                models = association.klass.find(model_params[attributes_key].map { |i| i['id'] }.compact)
                model_params[attributes_key].map { |i|
                  nested_record = i['id'] ? models.find { |r| r.id == i['id'] } : association.klass.new
                  i_params = filter_model_params(nested_record, i, allow_id: true)
                  nested_record.assign_attributes(i_params)
                  nested_record
                }
              else
                nested_record = model_params[attributes_key]['id'] ? association.klass.find(model_params[attributes_key]['id']) : association.klass.new
                i_params = filter_model_params(nested_record, model_params[attributes_key], allow_id: true)
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

          permitted_params.permit!
        end
      end

      permitted_params
    end

    def model_name(model)
      StandardAPI::AccessControlList.model_name(model)
    end

  end
end
