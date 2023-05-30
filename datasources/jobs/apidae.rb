# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/apidae'
require_relative '../destinations/geojson'


class Apidae < Job
  def initialize(multi_source_id, attribution, settings, path)
    super(multi_source_id, attribution, settings, path)

    job = Kiba.parse do
      source(ApidaeSource, multi_source_id, attribution, settings, path)
      destination(GeoJson, multi_source_id, path)
    end
    Kiba.run(job)
  end
end
