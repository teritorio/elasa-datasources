# typed: true
# frozen_string_literal: true

require 'test/unit'
require './datasources/transforms/join'

class JoinTransformerTags < Test::Unit::TestCase
  def setup
    @join = JoinTransformer.new('ref')
  end

  def join(current, update)
    @join.process_tags(current, update)
  end

  def test_other
    assert_equal(
      { 'ref' => 'a', 'phone' => '1' },
      join(
        { 'ref' => 'a', 'phone' => '1' },
        { 'ref' => 'a', 'phone' => '2' }
      )
    )
  end

  def test_addr
    assert_equal(
      { 'ref' => 'a', 'addr:street' => 'a' },
      join(
        { 'ref' => 'a', 'addr:street' => 'a' },
        { 'ref' => 'a', 'addr:street' => 'b' }
      )
    )
    assert_equal(
      { 'ref' => 'a', 'addr:street' => 'a', 'addr:city' => 'b' },
      join(
        { 'ref' => 'a', 'addr:street' => 'a', 'addr:city' => 'b' },
        { 'ref' => 'a', 'addr:housenumber' => '666' }
      )
    )
  end
end
