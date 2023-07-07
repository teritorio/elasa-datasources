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

  def setup(kiba, params)
    super(kiba, params)
    kiba.transform(OsmTags, params[2].merge({ 'extra_multiple' => %i[route_ref] }))
  end
end
