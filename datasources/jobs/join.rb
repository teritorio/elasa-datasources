# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/geojson'
require_relative '../transforms/join'
require_relative '../destinations/geojson'


class Join < Job
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    super(multi_source_id, attribution, settings, source_filter, path)

    job = Kiba.parse do
      settings['sources'].each{ |source_url|
        source(GeoJsonSource, multi_source_id, attribution, { source_url: source_url }, path)
      }
      transform(JoinTransformer, settings['key'])
      destination(GeoJson, multi_source_id, path)
    end
    Kiba.run(job)
  end
end
