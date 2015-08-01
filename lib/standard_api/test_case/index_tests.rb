module ActionController
  class StandardAPI < ActionController::Base
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

        test '#index.json mask' do
          m = create_model
          @api_key.update(mask: { plural_name => { id: m.id } })
          get :index, format: 'json'
          assert_equal model.where(id: m.id).to_sql, assigns(plural_name).to_sql
        end

        test '#index.json Total-Count header' do
          request.headers['Total-Count'] = ''
          get :index, format: 'json'
          assert_equal model.count.to_s, response.headers['Total-Count'].to_s
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
            if order.is_a?(Hash)
              order.values.last.each do |o|
                get :index, order: {order.keys.first => o}, format: 'json'
                assert_equal model.sort(order.keys.first => o).to_sql, assigns(plural_name).to_sql
              end
            else
              get :index, order: order, format: 'json'
              assert_equal model.sort(order).to_sql, assigns(plural_name).to_sql
            end
          end
        end

        test '#index.json params[:offset]' do
          get :index, offset: 13, format: 'json'
          assert_equal model.offset(13).to_sql, assigns(plural_name).to_sql
        end

        test '#index.json params[:include]' do
          create_model

          includes.each do |included|
            get :index, include: [included], format: 'json'
            assert JSON.parse(response.body)[0].key?(included.to_s), "#{included.inspect} not included in response"
          end
        end

        test 'route to #index.json' do
          assert_routing "/#{plural_name}", path_with_action('index')
          assert_recognizes path_with_action('index'), "/#{plural_name}"
        end
      
      end
    end
  end
end