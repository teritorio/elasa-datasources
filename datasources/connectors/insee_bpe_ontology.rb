# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'
require 'http'


require 'sorbet-runtime'

require_relative 'connector_ontology'
require_relative '../sources/insee_bpe'

class InseeBpeOntology < ConnectorOntology
  def setup(kiba)
    source_filter = @settings['filters']

    ontology, _schema, i18n, _osm_tags = parse_ontology(source_filter)
    kiba.source(MockSource, @job_id, nil, nil, MockSource::Settings.from_hash({
      'schema' => {
        'type' => 'object',
        # 'additionalProperties' => false,
        'properties' => {}, # schema,
      },
      'i18n' => i18n,
      'osm_tags' => [], # osm_tags,
    }))

    kiba.source(MetadataSource, @job_id, nil, nil, MetadataSource::Settings.from_hash({
      'schema' => [
        'datasources/schemas/tags/base.schema.json',
        'datasources/schemas/tags/any.schema.json',
      ],
      'i18n' => [
        'datasources/schemas/tags/base.i18n.json',
      ]
    }))

    if @source_filter.present?
      source_filter = @source_filter.split('-').reverse.inject(nil){ |sum, i| { i => sum } }
    end

    code_labels = ontology['group'].select{ |superclass_id, _superclasses|
      !source_filter ||
        source_filter.key?(superclass_id)
    }.collect{ |superclass_id, superclasses|
      superclasses['group'].select{ |class_id, _classes|
        !source_filter ||
          !source_filter[superclass_id] ||
          source_filter[superclass_id].key?(class_id)
      }.collect{ |class_id, classes|
        classes['group'].select{ |subclass_id, _subclasses|
          !source_filter ||
            !source_filter[superclass_id] ||
            !source_filter[superclass_id][class_id] ||
            source_filter[superclass_id][class_id].key?(subclass_id)
        }.collect{ |subclass_id, subclasses|
          [subclass_id, subclasses['label']]
        }
      }
    }.flatten(2).to_h

    kiba.source(
      InseeBpeSource,
      @job_id,
      'bpe',
      @settings.dig('metadata', 'name') || { 'fr-FR' => 'BPE' },
      InseeBpeSource::Settings.from_hash(@settings.merge({
        'code_labels' => code_labels,
      }))
    )
  end
end
