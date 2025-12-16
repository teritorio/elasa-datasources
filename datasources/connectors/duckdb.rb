# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/duckdb'
require_relative '../transforms/osm_tags'


class DuckdbConnector < Connector
  def self.source_class
    DuckdbSource
  end

  def setup(kiba)
    super
    kiba.transform(OsmTags, OsmTags::Settings.from_hash(@settings))
  end
end
