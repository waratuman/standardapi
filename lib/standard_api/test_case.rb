require 'active_support/test_case'

require File.expand_path(File.join(__FILE__, '../test_case/calculate_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/create_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/destroy_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/index_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/new_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/schema_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/show_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/update_tests'))

module StandardAPI::TestCase

  def assert_equal_or_nil(expected, *args)
    if expected.nil?
      assert_nil(*args)
    else
      assert_equal(expected, *args)
    end
  end

  def self.included(klass)
    [:filters, :includes].each do |attribute|
      klass.send(:class_attribute, attribute)
    end

    begin
      model_class = klass.name.gsub(/Test$/, '').constantize.model

      klass.send(:filters=, model_class.attribute_names)
      klass.send(:includes=, model_class.reflect_on_all_associations.map(&:name))
    rescue NameError => e
      raise e if e.message != "uninitialized constant #{model_class_name}"
    end

    klass.extend(ClassMethods)

    routes = Rails.application.routes.set.routes.inject({}) do |acc, r|
      acc[r.defaults[:controller]] ||= {}
      acc[r.defaults[:controller]][r.defaults[:action]] = true
      acc
    end

    test_cases = Dir.entries(File.expand_path(File.join(__FILE__, '..', 'test_case')))
    test_cases.select! {|fn| fn.ends_with?('_tests.rb') }
    test_cases.map! {|fn| fn.sub('_tests.rb', '') }
    (klass.controller_class.action_methods & test_cases).each do |action|
      if const_defined?("StandardAPI::TestCase::#{action.capitalize}Tests") && routes[klass.controller_class.controller_path][action]
        klass.include("StandardAPI::TestCase::#{action.capitalize}Tests".constantize)
      end
    end
  end

  def supports_format(format, action=nil)
    count = controller_class.view_paths.count do |path|
      !Dir.glob("#{path.instance_variable_get(:@path)}/{#{model.name.underscore},application}/**/#{action || '*'}.#{format}*").empty?
    end

    count > 0
  end

  # A controller to ask what the Policy permits the requests of the test. A
  # Policy is free to read the request, ie. the session or current user, so a
  # bare `controller_class.new`, which has none, won't do, and a made up
  # request wouldn't be the one the test makes. So it's the controller of the
  # last request the test made to +controller_class+ or, when that isn't the
  # last request of its session (none was made yet, another controller
  # answered, ie. to sign in, or the session was reset), of a GET it makes
  # for it, the way the test makes its own, to the first of
  # REQUEST_CONTROLLER_ACTIONS that's routed.
  #
  # Without one of those routes it's a controller with no request, as is
  # only right for a Policy that doesn't read one.
  def request_controller
    return @controller if request_controller?(@controller)

    REQUEST_CONTROLLER_ACTIONS.each do |action, params|
      path = begin
        resource_path(action, format: :json)
      rescue ActionController::UrlGenerationError
        next
      end

      get path, params: params
      break
    end

    request_controller?(@controller) ? @controller : controller_class.new
  end

  REQUEST_CONTROLLER_ACTIONS = { index: { limit: 1 }, schema: {}, calculate: {} }.freeze

  # Whether +controller+ answered the last request of the test, to
  # +controller_class+
  def request_controller?(controller)
    return false if !controller.is_a?(controller_class) || !controller.request
    # A controller test (ActionController::TestCase) has the one controller
    return true if !respond_to?(:integration_session)

    integration_session.controller.equal?(controller)
  end

  def orders
    request_controller.record_policy(model).orderable
  end

  def required_orders
    request_controller.record_policy(model).required_orders
  end

  def default_orders
    controller_class.new.send(:default_orders)
  end

  # Whether the model's Policy makes +where+ filterable
  def where_permitted?(where)
    controller = request_controller
    controller.send(:sanitize_wheres, where, controller.record_policy(model))
    true
  rescue StandardAPI::UnpermittedParameters
    false
  end

  def resource_limit
    controller_class.new.send(:resource_limit)
  end

  def default_limit
    controller_class.new.send(:default_limit)
  end

  def model
    self.class.model
  end

  def mask
    {}
  end

  def resource_path(action, options={})
    url_for({
      controller: controller_class.controller_path, action: action
    }.merge(options))
  end

  def controller_class
    self.class.controller_class
  end

  def create_model(attrs={})
    create(model.name.underscore, attrs.merge(mask))
  end

  def singular_name
    model.model_name.singular
  end

  def plural_name
    model.model_name.plural
  end

  def create_webmocks(attributes)
    attributes.each do |attribute, value|
      self.class.model.validators_on(attribute)
    end
  end

  def normalizers
    self.class.instance_variable_get('@normalizers')
  end

  def normalize_attribute(record, attribute, value)
    if normalizers[self.class.model] && normalizers[self.class.model][attribute]
      b = normalizers[self.class.model][attribute]
      b.arity == 2 ? b.call(record, value) : b.call(value)
    else
      # validators = self.class.model.validators_on(attribute)
      value
    end
  end

  def normalize_to_json(record, attribute, value)
    value = normalize_attribute(record, attribute, value)
    return nil if value.nil?

    if record.class.columns_hash[attribute.to_s]&.type == :decimal
      "#{value.to_f}"
    elsif value.is_a?(DateTime) #model.columns_hash[attribute].is_a?(ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter)
      value.in_time_zone.as_json
    else
      value.as_json
    end
  end

  def view_attributes(record)
    return [] if record.nil?
    policy = @controller.record_policy(record)
    record.attributes.select do |x|
      !policy.hidden?(x)
    end
  end

  # The attributes of +record+ an update could have written from its params,
  # so the ones to expect the params of the test in. +was+ is the record as it
  # was before the update, which is what its Policy decided for; without it,
  # the record as it is.
  def update_attributes(record, was = record)
    return {} if record.nil?
    record.attributes.slice(*written_attribute_names(was))
  end

  # The attributes of +record+ a create could have written from its params. A
  # create is of a new record, so that's what its Policy is asked about,
  # rather than +record+, which is saved by now: a new +model+, as
  # Controller#create builds, whatever subclass of it was created.
  def create_attributes(record)
    return {} if record.nil?
    new_record = record.is_a?(model) ? model.new : record.class.new
    record.attributes.slice(*written_attribute_names(new_record))
  end

  # The names of the attributes the params of a create of +record+, when it's
  # a new record, or else of an update of it, are written to: what its Policy
  # makes writable on that action (Policy::Record#writable), and the foreign
  # keys of the associations it makes writable, as
  # Controller#filter_model_params permits them. Less what the Policy assigns
  # on that action, which replaces what the params send, and what the model
  # makes attr_readonly.
  #
  # Visibility doesn't come into it: an +if+ or +unless+ decides what
  # renders, not what's writable.
  def written_attribute_names(record)
    policy = @controller.record_policy(record)

    names = policy.writable.flat_map { |name| name.is_a?(Hash) ? name.keys : [name] }
    policy.writable_associations.each do |name|
      reflection = record.class.reflect_on_association(name)
      names.concat(Array(reflection.foreign_key))
      names << reflection.foreign_type if reflection.polymorphic?
    end

    names.map(&:to_s).uniq - policy.assigned_attribute_names.map(&:to_s) - record.class.readonly_attributes.map(&:to_s)
  end

  module ClassMethods

    def self.extended(klass)
      klass.instance_variable_set('@normalizers', {})
    end

    def controller_class
      controller_class_name = self.name.gsub(/Test$/, '')
      controller_class_name.constantize
    rescue NameError => e
      raise e if e.message != "uninitialized constant #{controller_class_name}"
    end

    def model=(val)
      @model = val
      self.filters = val.attribute_names
      self.orders = val.attribute_names
      self.includes = val.reflect_on_all_associations.map(&:name)
      @model
    end

    def model
      return @model if defined?(@model) && @model

      klass_name = controller_class.name.gsub(/Controller$/, '').singularize

      begin
        @model = klass_name.constantize
      rescue NameError
        raise e unless e.message =~ /uninitialized constant #{klass_name}/
      end

      if @model.nil?
        raise "@model is nil: make sure you set it in your test using `self.model = ModelClass`."
      else
        @model
      end
    end

    def normalize(*attributes, &block)
      attributes.each do |attribute|
        @normalizers[model] ||= {}
        @normalizers[model][attribute] = block
      end
    end

  end

end
