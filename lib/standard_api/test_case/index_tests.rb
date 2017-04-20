module StandardAPI
  module TestCase
    module IndexTests
      extend ActiveSupport::Testing::Declarative

      test '#index.json' do
        get resource_path(:index, format: :json), params: { limit: 10, order: orders.first }
        assert_response :ok
        models = @controller.instance_variable_get("@#{plural_name}")
        assert_equal model.order(orders.first).limit(10).all.map(&:id).sort, models.map(&:id).sort
        assert JSON.parse(response.body).is_a?(Array)
      end

      test '#index.json requires limit' do
        limit = controller_class.new.send(:resource_limit)

        return if !limit || limit == Float::INFINITY

        begin
          get resource_path(:index, format: :json)
          assert_response :bad_request
        rescue ActionController::ParameterMissing
        end

        # return if !controller_class.new.send(:resource_limit)
        # if app.config.action_dispatch.show_exceptions
        #   assert_raises ActionController::ParameterMissing do
        #     get resource_path(:index, format: 'json')
        #     assert_response :bad_request
        #   end
        # else
        #   get resource_path(:index, format: :json)
        #   assert_response :bad_request
        # end
      end

      test '#index.json params[:limit]' do
        get resource_path(:index, format: :json), params: { limit: 1 }
        models = @controller.instance_variable_get("@#{plural_name}")
        assert_equal model.limit(1).sort(required_orders).to_sql, models.to_sql
      end

      test '#index.json params[:limit] does not exceed maximum limit' do
        assert_raises ActionController::UnpermittedParameters do
          get resource_path(:index, format: :json), params: { limit: 1000000 }
        end
      end

      test '#index.json params[:where]' do
        m = create_model

        get resource_path(:index, format: :json), params: { limit: 10, where: { id: m.id } }
        models = @controller.instance_variable_get("@#{plural_name}")
        assert_equal [m], models
      end

      test '#index.json params[:order]' do
        # This is just to instance @controller
        get resource_path(:index, format: :json), params: { limit: 1 }

        orders.each do |order|
          @controller.instance_variable_set('@orders', nil) # Hack for dealing with caching / multiple request per controller life
          get resource_path(:index, format: :json), params: { limit: 10, order: order }
          models = @controller.instance_variable_get("@#{plural_name}")
          assert_equal model.sort(order).limit(10).sort(required_orders).to_sql, models.to_sql
         end
      end

      test '#index.json params[:offset]' do
        get resource_path(:index, format: :json), params: { limit: 10, offset: 13 }
        models = @controller.instance_variable_get("@#{plural_name}")
        assert_equal model.offset(13).limit(10).sort(required_orders).to_sql, models.to_sql
      end

      test '#index.json params[:include]' do
        travel_to Time.now do
          create_model
          get resource_path(:index, format: :json), params: { limit: 100, include: includes }
        
          json = JSON.parse(response.body)[0]
          assert json.is_a?(Hash)
          includes.each do |included|
            assert json.key?(included.to_s), "#{included.inspect} not included in response"

            models = @controller.instance_variable_get("@#{plural_name}")
            association = models.first.class.reflect_on_association(included)
            next if !association

            if ['belongs_to', 'has_one'].include?(association.macro.to_s)
              models = @controller.instance_variable_get("@#{plural_name}")
              m = models.first.send(included)
              view_attributes(m) do |key, value|
                message = "Model / Attribute: #{m.class.name}##{key}"
                assert_equal json[included.to_s][key.to_s], normalize_to_json(m, key, value), message
              end
            else
              m = models.first.send(included).first.try(:reload)

              m_json = if m && m.has_attribute?(:id)
                json[included.to_s].find { |x| x['id'] == normalize_to_json(m, :id, m.id) }
              elsif m
                json[included.to_s].find { |x| x.keys.all? { |key| x[key] == normalize_to_json(m, key, m[key]) } }
              else
                nil
              end

              view_attributes(m).each do |key, value|
                message = "Model / Attribute: #{m.class.name}##{key}"
                if m_json[key.to_s].nil?
                  assert_nil normalize_to_json(m, key, value), message
                else
                  assert_equal m_json[key.to_s], normalize_to_json(m, key, value), message
                end
              end

            end
          end
        end
      end

      test '#index.json mask' do
        # This is just to instance @controller
        get resource_path(:index, format: :json), params: { limit: 1 }

        # If #current_mask isn't defined by StandardAPI we don't know how to
        # test other's implementation of #current_mask. Return and don't test.
        return if @controller.method(:current_mask).owner != StandardAPI

        m = create_model
        @controller.current_mask[plural_name] = { id: m.id }
        get :index, format: :json
        models = @controller.instance_variable_get("@#{plural_name}")
        assert_equal model.where(id: m.id).sort(required_orders).to_sql, models.to_sql
        @controller.current_mask.delete(plural_name)
      end
    end
  end
end
