# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/csv'
require_relative '../transforms/osm_tags'


class CsvConnector < Connector
  def self.source_class
    CsvSource
  end

  def setup(kiba)
    super(kiba)
    kiba.transform(OsmTags, OsmTags::Settings.from_hash(@settings))
  end
end
