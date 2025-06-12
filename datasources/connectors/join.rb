# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../destinations/gpx'
require_relative '../sources/gtfs_shape'
require_relative '../sources/gtfs_stop'


class Join < Connector
  def setup(kiba)
    key = @settings['key']
    joins = @settings['joins']
    joins.each{ |destination_id, join|
      join.each{ |source, source_config|
        kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
          'schema' => ["./#{@path}/#{source_config['metadata']}.schema.json"],
          'i18n' => ["./#{@path}/#{source_config['metadata']}.i18n.json"],
          'osm_tags' => source_config['osm_tags'] ? ["./#{@path}/#{source_config['osm_tags']}.osm_tags.json"] : nil,
        }))

        kiba.source(
          GeoJsonTagsNativesSource,
          @job_id,
          destination_id,
          nil,
          GeoJsonTagsNativesSource::Settings.from_hash({
            'url' => "file://./#{@path}/#{source}.geojson",
            'metadata' => JSON.parse(File.read("./#{@path}/#{source_config['metadata']}.metadata.json"))[source]
          })
        )

        kiba.transform(JoinTransformer, JoinTransformer::Settings.from_hash({
          'source_ids' => [join.keys],
          'destination_id' => destination_id,
          'key' => key,
          'full_join' => true,
        }))
      }
    }
  end
end
