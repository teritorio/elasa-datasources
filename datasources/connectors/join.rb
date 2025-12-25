# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/gtfs_shape'
require_relative '../sources/gtfs_stop'


class Join < Connector
  def setup(kiba)
    key = @settings['key']
    joins = @settings['joins']
    joins.each{ |destination_id, join|
      join.each{ |source, source_config|
        kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
          'schema' => ["./#{source_config['metadata']}.schema.json"],
          'i18n' => ["./#{source_config['metadata']}.i18n.json"],
          'osm_tags' => source_config['osm_tags'] ? ["./#{source_config['osm_tags']}.osm_tags.json"] : nil,
        }))

        metadata_path = "#{source_config['metadata']}.metadata.json"
        metadata_path = "internal/#{metadata_path}" if File.exist?("internal/#{metadata_path}")
        kiba.source(
          GeoJsonTagsNativesSource,
          @job_id,
          destination_id,
          nil,
          GeoJsonTagsNativesSource::Settings.from_hash({
            'url' => "file://./#{source}.geojson",
            'metadata' => JSON.parse(File.read(metadata_path))[source]
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
