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
          if order.is_a?(Hash)
            order.values.last.each do |o|
              get :index, order: {order.keys.first => o}, format: 'json'
              assert_equal model.sort(order.keys.first => o).to_sql, assigns(plural_name).to_sql
            end
          else
            get :index, order: order, format: 'json'
            assert_equal model.sort(order).to_sql, assigns(:records).to_sql
          end
        end
      end

      test '#index.json params[:offset]' do
        get :index, offset: 13, format: 'json'
        assert_equal model.offset(13).to_sql, assigns(:records).to_sql
      end

      test '#index.json params[:include]' do
        create_model
        get :index, include: includes, format: 'json'
        includes.each do |included|
          assert JSON.parse(response.body)[0].key?(included.to_s), "#{included.inspect} not included in response"
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
