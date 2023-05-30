# typed: true
# frozen_string_literal: true

require 'test/unit'
require './datasources/transforms/osm_tags'

class TestOsmTags < Test::Unit::TestCase
  def setup
    @osm_tags = OsmTags.new()
  end

  def map(tags)
    @osm_tags.process_tags(tags)
  end

  def test_split
    assert_equal({ 'phone' => %w[1 2] }, map({ 'phone' => '1;2' }))
    assert_equal({ 'foobar' => '1;2' }, map({ 'foobar' => '1;2' }))
  end

  def test_contact_social
    assert_equal({ 'facebook' => 'a' }, map({ 'facebook' => 'a' }))
    assert_equal({ 'facebook' => 'b' }, map({ 'contact:facebook' => 'b' }))
    assert_equal({ 'facebook' => 'a' }, map({ 'facebook' => 'a', 'contact:facebook' => 'b' }))
  end

  def test_contact_addr
    assert_equal({ 'addr:street' => 'a' }, map({ 'addr:street' => 'a' }))
    assert_equal({ 'addr:street' => 'b' }, map({ 'contact:street' => 'b' }))
    assert_equal({ 'addr:street' => 'a' }, map({ 'addr:street' => 'a', 'contact:street' => 'b' }))

    assert_equal({ 'addr:street' => 'a' }, map({ 'addr:street' => 'a', 'contact:street' => 'b', 'contact:housenumber' => '666' }))
  end
end
