require 'standard_api/test_helper'

class ExcludesTest < Minitest::Test

  SCHEMAS = StandardAPI::Excludes::SCHEMAS

  # = normalize

  def test_normalize_nil_and_empty
    assert_equal({}, StandardAPI::Excludes.normalize(nil).to_h)
    assert_equal({}, StandardAPI::Excludes.normalize({}).to_h)
  end

  def test_normalize_keeps_true_and_drops_what_excludes_nothing
    assert_equal(
      { 'a' => true },
      StandardAPI::Excludes.normalize(a: true, b: false, c: nil, d: {}, e: { SCHEMAS => [] }).to_h
    )
  end

  def test_normalize_keeps_the_schemas_narrowing_a_record
    schema = Class.new(StandardAPI::Schema)
    normalized = StandardAPI::Excludes.normalize(account: { SCHEMAS => schema })
    assert_equal [schema], normalized.dig('account', SCHEMAS)
  end

  def test_normalize_indifferent_access
    normalized = StandardAPI::Excludes.normalize(name: true)
    assert_equal true, normalized[:name]
    assert_equal true, normalized['name']
  end

  def test_normalize_merges_symbol_and_string_key_collisions
    a = Class.new(StandardAPI::Schema)
    b = Class.new(StandardAPI::Schema)
    normalized = StandardAPI::Excludes.normalize(:x => { SCHEMAS => [a] }, 'x' => { SCHEMAS => [b] })
    assert_equal [a, b], normalized.dig('x', SCHEMAS)
  end

  # = deep_merge

  def test_deep_merge_empty_sides
    assert_equal({ 'a' => true }, StandardAPI::Excludes.deep_merge(nil, { a: true }).to_h)
    assert_equal({ 'a' => true }, StandardAPI::Excludes.deep_merge({ a: true }, {}).to_h)
  end

  def test_deep_merge_true_wins_over_a_hash
    schema = Class.new(StandardAPI::Schema)
    merged = StandardAPI::Excludes.deep_merge({ account: { SCHEMAS => [schema] } }, { account: true })
    assert_equal({ 'account' => true }, merged.to_h)
    assert_equal true, StandardAPI::Excludes.deep_merge(true, { a: true })
  end

  def test_deep_merge_applies_the_schemas_of_both
    a = Class.new(StandardAPI::Schema)
    b = Class.new(StandardAPI::Schema)
    merged = StandardAPI::Excludes.deep_merge({ account: { SCHEMAS => [a] } }, { account: { SCHEMAS => [b, a] } })
    assert_equal [a, b], merged.dig('account', SCHEMAS)
  end

end
