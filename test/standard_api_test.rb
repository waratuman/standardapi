require 'test_helper'

class PropertiesControllerTest < ActionController::TestCase
  include StandardAPI::TestCase

  # = Routing Tests
  # These also can't be included in StandardAPI::TestCase because we don't know
  # how the other's routes are setup
  test 'route to #create.json' do
    assert_routing({ method: :post, path: "/#{plural_name}" }, path_with_action('create'))
    assert_recognizes(path_with_action('create'), { method: :post, path: "/#{plural_name}" })
  end

  test 'route to #calculate.json' do
    assert_routing "/#{plural_name}/calculate", path_with_action('calculate')
    assert_recognizes(path_with_action('calculate'), "/#{plural_name}/calculate")
  end

  test 'route to #destroy.json' do
    assert_routing({ method: :delete, path: "/#{plural_name}/1" }, path_with_action('destroy', id: '1'))
    assert_recognizes(path_with_action('destroy', id: '1'), { method: :delete, path: "/#{plural_name}/1" })
  end

  test 'route to #index.json' do
    assert_routing "/#{plural_name}", path_with_action('index')
    assert_recognizes path_with_action('index'), "/#{plural_name}"
  end

  test 'route to #show.json' do
    assert_routing "/#{plural_name}/1", path_with_action('show', id: '1')
    assert_recognizes(path_with_action('show', id: '1'), "/#{plural_name}/1")
  end

  test 'route to #update.json' do
    assert_routing({ method: :put, path: "#{plural_name}/1" }, path_with_action('update', id: '1'))
    assert_recognizes(path_with_action('update', id: '1'), { method: :put, path: "/#{plural_name}/1" })
    assert_routing({ method: :patch, path: "/#{plural_name}/1" }, path_with_action('update', id: '1'))
    assert_recognizes(path_with_action('update', id: '1'), { method: :patch, path: "/#{plural_name}/1" })
  end

  test 'route to #schema.json' do
    assert_routing({ method: :post, path: "/#{plural_name}/schema" }, path_with_action('schema'))
    assert_recognizes(path_with_action('schema'), { method: :post, path: "/#{plural_name}/schema" })
  end

  # View Tests
  
  # test '#index.json uses overridden partial'
  # test '#show.json uses overridden partial'
  # test '#schema.json uses overridden partial'
  # test 'append_view_path'

  # Includes Test

  test 'Includes::normailze' do
    method = StandardAPI::Includes.method(:normalize)
    assert_equal method.call(:x), { 'x' => {} }
    assert_equal method.call([:x, :y]), { 'x' => {}, 'y' => {} }
    assert_equal method.call([ { x: true }, { y: true } ]), { 'x' => {}, 'y' => {} }
    assert_equal method.call({ x: true, y: true }), { 'x' => {}, 'y' => {} }
    assert_equal method.call({ x: { y: true } }), { 'x' => { 'y' => {} } }
    assert_equal method.call({ x: { y: {} } }), { 'x' => { 'y' => {} } }
    assert_equal method.call({ x: [:y] }), { 'x' => { 'y' => {} } }
  end

  # sanitize({:key => {}}, [:key]) # => {:key => {}}
  # sanitize({:key => {}}, {:key => true}) # => {:key => {}}
  # sanitize({:key => {}}, :value => {}}, [:key]) => # Raises ParseError
  # sanitize({:key => {}}, :value => {}}, {:key => true}) => # Raises ParseError
  # sanitize({:key => {:value => {}}}, {:key => [:value]}) # => {:key => {:value => {}}}
  # sanitize({:key => {:value => {}}}, {:key => {:value => true}}) # => {:key => {:value => {}}}
  # sanitize({:key => {:value => {}}}, [:key]) => # Raises ParseError
  test 'Includes::sanitize' do
    method = StandardAPI::Includes.method(:sanitize)
    assert_equal method.call(:x, [:x]), { 'x' => {} }
    assert_equal method.call(:x, {:x => true}), { 'x' => {} }
    
    assert_raises(ActionDispatch::ParamsParser::ParseError) do
      method.call([:x, :y], [:x])
    end

    assert_raises(ActionDispatch::ParamsParser::ParseError) do
      method.call([:x, :y], {:x => true})
    end

    assert_raises(ActionDispatch::ParamsParser::ParseError) do
      method.call({:x => true, :y => true}, [:x])
    end
    assert_raises(ActionDispatch::ParamsParser::ParseError) do
      method.call({:x => true, :y => true}, {:x => true})
    end
    assert_raises(ActionDispatch::ParamsParser::ParseError) do
      method.call({ x: { y: true }}, { x: true })
    end

    assert_equal method.call({ x: { y: true }}, { x: { y: true } }), { 'x' => { 'y' => {} } }
  end

  # Order Test

  test 'Orders::sanitize(:column, [:column])' do
    method = StandardAPI::Orders.method(:sanitize)

    assert_equal :x, method.call(:x, :x)
    assert_equal :x, method.call(:x, [:x])
    assert_equal [:x], method.call([:x], [:x])
    assert_raises(ActionDispatch::ParamsParser::ParseError) do
      method.call(:x, :y)
    end

    assert_equal({ x: :asc }, method.call({ x: :asc }, :x))
    assert_equal({ x: :desc }, method.call({ x: :desc }, :x))
    assert_equal([{ x: :asc }], method.call([{ x: :asc }], :x))
    assert_equal([{ x: :desc }], method.call([{ x: :desc }], :x))
    assert_equal([{ x: { asc: :nulls_last } }], method.call([{ x: { asc: :nulls_last } }], :x))
    assert_equal([{ x: { asc: :nulls_first } }], method.call([{ x: { asc: :nulls_first } }], :x))
    assert_equal([{ x: { desc: :nulls_last } }], method.call([{ x: { desc: :nulls_last } }], :x))
    assert_equal([{ x: { desc: :nulls_first }}], method.call([{ x: { desc: :nulls_first } }], :x))
    assert_equal([{ relation: :id }], method.call(['relation.id'], { relation: :id }))
    assert_equal([{ relation: :id }], method.call([{ relation: :id }], { relation: :id }))
    assert_equal([{ relation: :id }], method.call([{ relation: :id }], [{ relation: :id }]))
    assert_equal([{ relation: [:id] }], method.call([{ relation: [:id] }], { relation: [:id] }))
    assert_equal([{ relation: [:id] }], method.call([{ relation: [:id] }], [{ relation: [:id] }]))
    assert_equal([{ relation: { id: :desc } }], method.call([{'relation.id' => :desc}], { relation: :id }))
    assert_equal([{ relation: { id: :desc } }], method.call([{ relation: { id: :desc } }], { relation: [:id] }))
    assert_equal([{ relation: { id: :desc } }], method.call([{ relation: { id: :desc } }], [{ relation: [:id] }]))
    assert_equal([{ relation: [{ id: :desc }] }], method.call([{ relation: [{ id: :desc }] }], [{ relation: [:id] }]))
    assert_equal([{ relation: [{ id: :desc }] }], method.call([{ relation: [{ id: :desc }] }], [{ relation: [:id] }]))
    assert_equal([{ relation: {:id => {:asc => :nulls_last}} }], method.call([{ relation: {:id => {:asc => :nulls_last}} }], [{ relation: [:id] }]))
    assert_equal([{ relation: {:id => {:asc => :nulls_last}} }], method.call([{ relation: {:id => {:asc => :nulls_last}} }], [{ relation: [:id] }]))
    assert_equal([{ relation: {:id => [{:asc => :nulls_last}]} }], method.call([{ relation: {:id => [{:asc => :nulls_last}]} }], [{ relation: [:id] }]))
    assert_equal([{ relation: {:id => [{:asc => :nulls_last}]} }], method.call([{ relation: {:id => [{:asc => :nulls_last}]} }], [{ relation: [:id] }]))
  end

end
