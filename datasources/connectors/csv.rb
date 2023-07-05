# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/csv'
require_relative '../transforms/osm_tags'


class CsvJob < Connector
  def initialize(multi_source_id, settings, source_filter, path)
    super(multi_source_id, settings, source_filter, path)
    yield [
      self,
      multi_source_id,
      [CsvSource, settings]
    ]
  end

  def setup(kiba, params, *_args)
    super(kiba, params)
    kiba.transform(OsmTags, params[1].merge({ 'extra_multiple' => %i[route_ref] }))
  end
end
