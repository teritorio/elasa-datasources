# typed: true
# frozen_string_literal: true

require 'test/unit'
require './datasources/transforms/osm_tags'

class TestOsmTags < Test::Unit::TestCase
  def setup
    @osm_tags = OsmTags.new(OsmTags::Settings.from_hash({}))
  end

  def map(tags)
    @osm_tags.process_tags(tags)
  end

  def test_split
    assert_equal({ phone: %w[1 2] }, map({ phone: '1;2' }))
    assert_equal({ foobar: '1;2' }, map({ foobar: '1;2' }))
  end

  def test_contact_social
    assert_equal({ facebook: 'https://www.facebook.com/a' }, map({ facebook: 'a' }))
    assert_equal({ facebook: 'https://www.facebook.com/b' }, map({ 'contact:facebook': 'b' }))
    assert_equal({ facebook: 'https://www.facebook.com/a' }, map({ facebook: 'a', 'contact:facebook': 'b' }))
  end

  def test_contact_addr
    assert_equal({ addr: { 'street' => 'a' } }, map({ 'addr:street' => 'a' }))
    assert_equal({ addr: { 'street' => 'b' } }, map({ 'contact:street' => 'b' }))
    assert_equal({ addr: { 'street' => 'a' } }, map({ 'addr:street' => 'a', 'contact:street' => 'b' }))
    assert_equal({ addr: { 'street' => 'a' } }, map({ 'addr:street' => 'a', 'contact:street' => 'b', 'contact:housenumber' => '666' }))
  end

  def test_name
    assert_equal({ name: { 'fr-FR' => 'a' } }, map({ 'name' => 'a' }))
    assert_equal({ name: { 'fr-FR' => 'a', 'oc' => 'r' } }, map({ 'name' => 'a', 'name:oc' => 'r', 'name:wiki' => 'b' }))
    assert_equal({ name: { 'fr-FR' => 'a' } }, map({ 'name:fr-FR' => 'a' }))
  end

  def test_default_name
    assert_equal({ name: { 'fr-FR' => 'a' }, alt_name: { 'fr-FR' => 'a' } }, map({ 'alt_name' => 'a' }))
    assert_equal({ name: { 'fr-FR' => 'a', 'de-DE' => 'b' }, alt_name: { 'de-DE' => 'b' } }, map({ 'name:fr-FR' => 'a', 'alt_name:de-DE' => 'b' }))
  end

  def test_url_formatter
    assert_equal({ facebook: 'https://www.facebook.com/a' }, map({ 'facebook' => 'a' }))
    assert_equal({ facebook: 'https://face.book' }, map({ 'facebook' => 'https://face.book' }))
  end
end
