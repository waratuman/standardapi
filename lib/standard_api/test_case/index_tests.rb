module StandardAPI
  module TestCase
    module IndexTests
      extend ActiveSupport::Testing::Declarative

      test '#index.json' do
        get :index, format: 'json'
        assert_response :ok
        assert_template :index
        assert_equal model.all.map(&:id).sort, assigns(plural_name).map(&:id).sort
        assert JSON.parse(response.body).is_a?(Array)
      end

      test '#index.json params[:limit]' do
        get :index, limit: 1, format: 'json'
        assert_equal model.limit(1).to_sql, assigns(plural_name).to_sql
      end

      test '#index.json params[:where]' do
        m = create_model
        get :index, where: { id: m.id }, format: 'json'
        assert_equal [m], assigns(plural_name)
      end

      test '#index.json params[:order]' do
        orders.each do |order|
          @controller.instance_variable_set('@orders', nil) # Hack for dealing with caching / multiple request per controller life
          get :index, order: order, format: 'json'
          assert_equal model.sort(order).to_sql, assigns(plural_name).to_sql
         end
      end

      test '#index.json params[:offset]' do
        get :index, offset: 13, format: 'json'
        assert_equal model.offset(13).to_sql, assigns(plural_name).to_sql
      end

      test '#index.json params[:include]' do
        travel_to Time.now do
          create_model
          get :index, include: includes, format: 'json'
        
          json = JSON.parse(response.body)[0]
          assert json.is_a?(Hash)
          includes.each do |included|
            assert json.key?(included.to_s), "#{included.inspect} not included in response"

            association = assigns(plural_name).first.class.reflect_on_association(included)
            next if !association

            if ['belongs_to', 'has_one'].include?(association.macro.to_s)
              m = assigns(plural_name).first.send(included)
              view_attributes(m) do |key, value|
                message = "Model / Attribute: #{m.class.name}##{key}"
                assert_equal json[included.to_s][key.to_s], normalize_to_json(m, key, value), message
              end
            else
              m = assigns(plural_name).first.send(included).first.try(:reload)

              m_json = if m && m.has_attribute?(:id)
                json[included.to_s].find { |x| x['id'] == normalize_to_json(m, :id, m.id) }
              elsif m
                json[included.to_s].find { |x| x.keys.all? { |key| x[key] == normalize_to_json(m, key, m[key]) } }
              else
                nil
              end

              view_attributes(m).each do |key, value|
                message = "Model / Attribute: #{m.class.name}##{key}"
                assert_equal m_json[key.to_s], normalize_to_json(m, key, value)
              end

            end
          end
        end
      end

      test '#index.json mask' do
        # If #current_mask isn't defined by StandardAPI we don't know how to
        # test other's implementation of #current_mask. Return and don't test.
        return if @controller.method(:current_mask).owner != StandardAPI

        m = create_model
        @controller.current_mask[plural_name] = { id: m.id }
        get :index, format: 'json'
        assert_equal model.where(id: m.id).to_sql, assigns(plural_name).to_sql
        @controller.current_mask.delete(plural_name)
      end

    end
  end
end
