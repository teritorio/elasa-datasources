# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/overpass_select'


class OverpassSelect < Connector
  def self.source_class
    OverpassSelectSource
  end

  def setup(kiba)
    kiba.source(MetadataSource, @job_id, nil, nil, MetadataSource::Settings.from_hash({
      'schema' => [
        'datasources/schemas/tags/base.schema.json',
        'datasources/schemas/tags/any.schema.json',
      ],
      'i18n' => [
        'datasources/schemas/tags/base.i18n.json',
      ]
    }))

    super

    kiba.transform(OsmTags, OsmTags::Settings.from_hash(@settings))

    return unless @settings['georeverse']

    kiba.transform(ReverseGeocode, Transformer::TransformerSettings.from_hash({}))
  end
end
