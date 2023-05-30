# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/geotrek'
require_relative '../destinations/geojson_by'


class Geotrek < Job
  def initialize(multi_source_id, attribution, settings, path)
    super(multi_source_id, attribution, settings, path)

    job = Kiba.parse do
      source(GeotrekSource, multi_source_id, attribution, settings, path)
      destination(GeoJsonBy, path)
    end
    Kiba.run(job)
  end
end
