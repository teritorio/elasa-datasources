# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/overpass_select'


class OverpassSelect < Connector
  def self.source_class
    OverpassSelectSource
  end

  def setup(kiba)
    super(kiba)
    kiba.transform(OsmTags, @settings)
  end
end
