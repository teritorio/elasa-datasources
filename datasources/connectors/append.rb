# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/geojson_tags_natives'


class Append < Connector
  def setup(kiba)
    appends = @settings['appends']

    appends.each{ |destination_id, append|
      append['sources'].each{ |source|
        kiba.source(
          GeoJsonTagsNativesSource,
          @job_id,
          destination_id,
          append['metadata']['name'],
          GeoJsonTagsNativesSource::Settings.from_hash({
            'url' => "file://./#{source}.geojson",
            # 'metadata' => Source::Metadata.from_hash(append['metadata']),
            'metadata' => append['metadata'],
          })
        )
      }
    }
  end
end
