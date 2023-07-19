# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class MockSource < Source
  def i18n
    super.merge(
      @settings[:i18n] || {}
    )
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
