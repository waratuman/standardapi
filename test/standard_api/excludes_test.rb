require 'standard_api/test_helper'

class ExcludesTest < Minitest::Test

  # = normalize

  def test_normalize_nil_and_empty
    assert_equal({}, StandardAPI::Excludes.normalize(nil).to_h)
    assert_equal({}, StandardAPI::Excludes.normalize([]).to_h)
    assert_equal({}, StandardAPI::Excludes.normalize({}).to_h)
  end

  def test_normalize_symbol
    assert_equal({ 'name' => true }, StandardAPI::Excludes.normalize(:name).to_h)
  end

  def test_normalize_flat_array
    assert_equal(
      { 'a' => true, 'b' => true },
      StandardAPI::Excludes.normalize([:a, :b]).to_h
    )
  end

  def test_normalize_hash_with_array_value
    assert_equal(
      { 'players' => { 'name' => true } },
      StandardAPI::Excludes.normalize({ players: [:name] }).to_h
    )
  end

  def test_normalize_hash_with_true_value
    assert_equal(
      { 'description' => true, 'players' => { 'name' => true } },
      StandardAPI::Excludes.normalize({ description: true, players: { name: true } }).to_h
    )
  end

  def test_normalize_mixed_array
    assert_equal(
      { 'description' => true, 'players' => { 'name' => true } },
      StandardAPI::Excludes.normalize([:description, { players: [:name] }]).to_h
    )
  end

  def test_normalize_indifferent_access
    result = StandardAPI::Excludes.normalize({ 'name' => true })
    assert_equal(true, result[:name])
    assert_equal(true, result['name'])
  end

  def test_normalize_is_idempotent
    once = StandardAPI::Excludes.normalize({ players: [:name] })
    twice = StandardAPI::Excludes.normalize(once)
    assert_equal(once.to_h, twice.to_h)
  end

  # = deep_merge

  def test_deep_merge_empty_sides
    a = { 'name' => true }
    assert_equal({ 'name' => true }, StandardAPI::Excludes.deep_merge(a, nil).to_h)
    assert_equal({ 'name' => true }, StandardAPI::Excludes.deep_merge(nil, a).to_h)
    assert_equal({ 'name' => true }, StandardAPI::Excludes.deep_merge(a, {}).to_h)
    assert_equal({ 'name' => true }, StandardAPI::Excludes.deep_merge({}, a).to_h)
  end

  def test_deep_merge_disjoint_keys
    a = { description: true }
    b = { photos: [:format] }
    assert_equal(
      { 'description' => true, 'photos' => { 'format' => true } },
      StandardAPI::Excludes.deep_merge(a, b).to_h
    )
  end

  def test_deep_merge_true_wins_over_hash
    # If either side says "hide this whole thing", we hide it all.
    a = { photos: true }
    b = { photos: [:format] }
    assert_equal({ 'photos' => true }, StandardAPI::Excludes.deep_merge(a, b).to_h)
    assert_equal({ 'photos' => true }, StandardAPI::Excludes.deep_merge(b, a).to_h)
  end

  def test_deep_merge_nested_hashes_recurse
    a = { photos: { format: true } }
    b = { photos: { caption: true } }
    assert_equal(
      { 'photos' => { 'format' => true, 'caption' => true } },
      StandardAPI::Excludes.deep_merge(a, b).to_h
    )
  end

  def test_deep_merge_accepts_unnormalized_input
    a = [:description]
    b = { photos: [:format] }
    assert_equal(
      { 'description' => true, 'photos' => { 'format' => true } },
      StandardAPI::Excludes.deep_merge(a, b).to_h
    )
  end

end
