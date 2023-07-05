# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/csv'
require_relative '../transforms/osm_tags'


class CsvJob < Connector
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    super(multi_source_id, attribution, settings, source_filter, path)
    yield [
      self,
      [CsvSource, multi_source_id, attribution, settings]
    ]
  end

  def setup(kiba, params, *_args)
    super(kiba, params)
    kiba.transform(OsmTags, %i[route_ref])
  end
end
