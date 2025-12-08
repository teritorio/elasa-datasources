# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/gtfs_shape'
require_relative '../sources/gtfs_stop'


class Gtfs < Connector
  def setup(kiba)
    kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
      'tags_schema_file' => [
        '../../datasources/schemas/tags/base.schema.json',
        # '../../datasources/schemas/tags/bus.schema.json',
        '../../datasources/schemas/tags/bus-gtfs.schema.json', # TEMP FIXME to be removed
      ],
      'i18n_file' => [
        '../../datasources/schemas/tags/base.i18n.json',
        # '../../datasources/schemas/tags/bus.i18n.json',
        '../../datasources/schemas/tags/bus-gtfs.i18n.json', # TEMP FIXME to be removed
      ],
    }))

    kiba.source(
      GtfsShapeSource,
      @job_id,
      "#{@job_id}-shape",
      @settings['name'] || { 'en-US' => 'gtfs-shape' },
      GtfsShapeSource::Settings.from_hash(@settings),
    )

    kiba.source(
      GtfsStopSource,
      @job_id,
      "#{@job_id}-stop",
      @settings['name'] || { 'en-US' => 'gtfs-stop' },
      GtfsStopSource::Settings.from_hash(@settings),
    )
  end
end
