# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/csv'
require_relative '../transforms/osm_tags'
require_relative '../destinations/geojson'


class CsvJob < Job
  def initialize(multi_source_id, attribution, settings, path)
    super(multi_source_id, attribution, settings, path)

    job = Kiba.parse do
      source(CsvSource, multi_source_id, attribution, settings, path)
      transform(OsmTags, %w[route_ref])
      destination(GeoJson, multi_source_id, path)
    end
    Kiba.run(job)
  end
end
