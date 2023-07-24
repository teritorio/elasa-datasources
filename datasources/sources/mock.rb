# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class MockSource < Source
  def schema
    super.merge({
      schema: @settings[:schema],
      i18n: @settings[:i18n],
  }.compact)
  end

  def osm_tags
    super.merge(
      @settings[:osm_tags] || {}
    )
  end

  def each
    super([])
  end
end
