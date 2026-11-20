require 'standard_api/test_helper'

# StandardAPI::TestCase, run against NotesController, whose Policy makes
# +title+ writable only on create, assigns +author_id+, and makes +rank+
# orderable and filterable only to a signed in session. The generated tests
# make their requests signed in.
class NotesControllerTest < ActionDispatch::IntegrationTest
  include StandardAPI::TestCase

  setup do
    post sessions_path(format: :json), params: { user_id: 7 }
    assert_response :ok
  end

  test 'TestCase#orders, #required_orders and #where_permitted? are what the Policy permits the session of the test' do
    assert_equal %w[id rank], orders.sort
    assert_equal [], required_orders
    assert where_permitted?({ rank: 1 })
    assert_not where_permitted?({ title: 'a' })
  end

  test 'TestCase#orders and #where_permitted? are what the Policy permits a session that is not signed in' do
    reset!

    assert_equal %w[id], orders
    assert where_permitted?({ id: 1 })
    assert_not where_permitted?({ rank: 1 })
  end

  test 'TestCase#orders follows the session after a request was made' do
    get resource_path(:index, format: :json), params: { limit: 1 }
    assert_equal %w[id rank], orders.sort

    reset!
    assert_equal %w[id], orders
  end

  test 'TestCase#create_attributes and #update_attributes are what the Policy makes writable on each, less what it assigns' do
    note = create(:note)
    get resource_path(:show, id: note.id, format: :json)

    assert_equal %w[body title], create_attributes(note).keys.sort
    assert_equal %w[body], update_attributes(note).keys
  end

  test 'POST create writes what is writable on create, and what the Policy assigns' do
    post resource_path(:create, format: :json), params: { note: { title: 'A', body: 'B', author_id: 999, rank: 3 } }, as: :json
    assert_response :created

    assert_equal({ 'title' => 'A', 'body' => 'B', 'author_id' => 7, 'rank' => nil }, Note.last.attributes.except('id'))
  end

  test 'PUT update writes what is writable on update, and what the Policy assigns' do
    note = create(:note, title: 'A', body: 'B', author_id: 1)
    put resource_path(:update, id: note.id, format: :json), params: { note: { title: 'C', body: 'D', author_id: 999, rank: 3 } }, as: :json
    assert_response :ok

    assert_equal({ 'title' => 'A', 'body' => 'D', 'author_id' => 7, 'rank' => nil }, note.reload.attributes.except('id'))
  end
end
