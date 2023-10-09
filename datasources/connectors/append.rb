# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/geojson'


class Append < Connector
  def setup(kiba)
    appends = @settings['appends']

    appends.each{ |destination_id, append|
      append['sources'].each{ |source|
        kiba.source(
          GeoJsonSource,
          @job_id,
          destination_id,
          append['metadata']['name'],
          GeoJsonSource::Settings.from_hash({
            'url' => "file://./#{@path}/#{source}.geojson",
            # 'metadata' => Source::Metadata.from_hash(append['metadata']),
            'metadata' => append['metadata'],
          })
        )
      }
    }
  end
end
