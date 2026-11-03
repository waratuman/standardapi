module StandardAPI
  # What AccessControlList and Schemas share: a module of methods for one
  # model (an ACL, or a controller's Schema) is included into the base
  # controller with its methods renamed under the model's name, ie.
  # +attributes+ as +photo_attributes+, so every controller can call them for
  # any model, and they are looked up by that name.
  module ModelModules

    # Yield the base controller, the +const+ module nested in it and the
    # model's prefix for each controller with a +const+ module, ie.
    # PhotosController::ACL. The base controller is the topmost class that
    # includes +owner+ (AccessControlList or Schemas). Controllers must
    # already be loaded for their modules to be found, so the Railtie calls
    # this once they are, at boot and after each reload.
    def self.each_nested(owner, const)
      ActionController::Metal.descendants.each do |controller|
        next if !controller.const_defined?(const, false)

        # Only a controller using StandardAPI has a model; any other
        # controller's constant is none of our business
        base = controller.ancestors.grep(Class).select { |c| c.include?(owner) }.last
        next if !base || !controller.model

        yield base, controller.const_get(const, false), controller.model.model_name.singular
      end
    end

    # Rename the methods of +mod+ in +renames+ (+{ attributes:
    # 'photo_attributes' }+) and include it into +application_controller+. A
    # module already renamed is left as it is. Raises if another module
    # included this way defines any of the same methods, as one would silently
    # override the other.
    def self.include_renamed(application_controller, mod, renames)
      renames.each do |from, to|
        next if !mod.instance_methods.include?(from)
        mod.send :alias_method, to.to_sym, from
        mod.send :remove_method, from
      end
      mod.instance_variable_set(:@standard_api_model_module, true)

      others = application_controller.ancestors.select { |m|
        m != mod && m.instance_variable_get(:@standard_api_model_module)
      }
      (mod.instance_methods(false) + mod.private_instance_methods(false)).each do |method|
        other = others.find { |m| m.method_defined?(method, false) || m.private_method_defined?(method, false) }
        next if !other

        raise StandardAPI::InvalidConfiguration, "#{ mod.name } and #{ other.name } both define #{ method }; the ACLs and Schemas of one model are shared by all of its controllers, so define them once"
      end

      application_controller.include mod
    end

    # The renamed method +name+ for +model+, ie. +property_attributes+,
    # falling back to the one for its base class (ie. an STI subclass), or nil
    # if there is none
    def model_method_for(model, name)
      [model, model.base_class].uniq.map { |k| "#{model_name(k)}_#{name}" }.find do |method|
        self.respond_to?(method, true)
      end
    end

    # The prefix +model+'s methods are renamed under
    def model_name(model)
      if model.model_name.singular.starts_with?('habtm_')
        model.reflect_on_all_associations.map { |a| a.klass.base_class.model_name.singular }.sort.join('_')
      else
        model.model_name.singular
      end
    end

  end
end
