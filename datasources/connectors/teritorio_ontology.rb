# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'
require 'http'


require 'sorbet-runtime'

require_relative 'connector_ontology'
require_relative '../sources/overpass_select'
require_relative '../sources/mock'
require_relative '../transforms/osm_tags'
require_relative '../transforms/reverse_geocode'

class TeritorioOntology < ConnectorOntology
  def setup(kiba)
    source_filter = @settings['filters']
    output_prefix = @settings['output_prefix'] ? "#{@settings['output_prefix']}-" : ''

    ontology, schema, i18n, osm_tags = parse_ontology(source_filter)
    kiba.source(MockSource, @job_id, nil, nil, MockSource::Settings.from_hash({
      'schema' => {
        'type' => 'object',
        'additionalProperties' => false,
        'properties' => schema,
      },
      'i18n' => i18n,
      'osm_tags' => osm_tags,
    }))

    kiba.source(MetadataSource, @job_id, nil, nil, MetadataSource::Settings.from_hash({
      'schema' => [
        'datasources/schemas/tags/base.schema.json',
        'datasources/schemas/tags/hosting.schema.json',
        'datasources/schemas/tags/restaurant.schema.json',
        'datasources/schemas/tags/osm.schema.json',
        'datasources/schemas/tags/any.schema.json',
      ],
      'i18n' => [
        'datasources/schemas/tags/base.i18n.json',
        'datasources/schemas/tags/hosting.i18n.json',
        'datasources/schemas/tags/restaurant.i18n.json',
        'datasources/schemas/tags/osm.i18n.json',
      ]
    }))

    if @source_filter.present?
      keys = @source_filter.split('-')
      source_filter = keys.reverse.inject(source_filter.dig(*keys)){ |sum, i| { i => sum } }
    end

    ontology['group'].select{ |superclass_id, _superclasses|
      !source_filter ||
        source_filter.key?(superclass_id)
    }.each{ |superclass_id, superclasses|
      superclasses['group'].select{ |class_id, _classes|
        !source_filter ||
          !source_filter[superclass_id] ||
          source_filter[superclass_id].key?(class_id)
      }.each{ |class_id, classes|
        if classes['group']
          classes['group'].select{ |subclass_id, _subclasses|
            !source_filter ||
              !source_filter[superclass_id] ||
              !source_filter[superclass_id][class_id] ||
              source_filter[superclass_id][class_id].key?(subclass_id)
          }.each{ |subclass_id, subclasses|
            kiba.source(
              OverpassSelectSource,
              @job_id,
              "#{output_prefix}#{superclass_id}-#{class_id}-#{subclass_id}",
              subclasses['label'],
              OverpassSelectSource::Settings.from_hash(@settings
                .merge({ 'select' => subclasses['osm_selector'], 'with_osm_tags' => false })
                .merge(source_filter.dig(superclass_id, class_id, subclass_id) || {})),
            )
          }
        else
          kiba.source(
            OverpassSelectSource,
            @job_id,
            "#{output_prefix}#{superclass_id}-#{class_id}",
            classes['label'],
            OverpassSelectSource::Settings.from_hash(@settings
              .merge({ 'select' => classes['osm_selector'], 'with_osm_tags' => false })
              .merge(source_filter.dig(superclass_id, class_id) || {})),
          )
        end
      }
    }

    kiba.transform(OsmTags, OsmTags::Settings.from_hash({}))

    return unless @settings['georeverse']

    kiba.transform(ReverseGeocode, Transformer::TransformerSettings.from_hash({}))
  end
end
