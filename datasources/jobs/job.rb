# frozen_string_literal: true
# typed: false

require 'sorbet-runtime'

require './datasources/connectors/apidae'
require './datasources/connectors/append'
require './datasources/connectors/csv'
require './datasources/connectors/geotrek'
require './datasources/connectors/join'
require './datasources/connectors/gtfs'
require './datasources/connectors/overpass_select'
require './datasources/connectors/teritorio_ontology'
require './datasources/connectors/tourinsoft_cdt50'
require './datasources/connectors/tourinsoft_sirtaqui'
require './datasources/connectors/tourinsoft_v3_sirtaqui'
require './datasources/connectors/tourism_system'
require './datasources/connectors/open_agenda'
require './datasources/sources/geojson'
require './datasources/destinations/destination'
require './datasources/destinations/geojson'
require './datasources/transforms/derivated_tag'
require './datasources/transforms/end_date'
require './datasources/transforms/join'
require './datasources/transforms/metadata_merge'
require './datasources/transforms/refs_integrity'
require './datasources/transforms/sanitize_tags'
require './datasources/transforms/validate'


class Job
  def initialize(job_id, tasks, source_filter, path)
    tasks = tasks.collect{ |taks_id, task|
      {
          id: taks_id,
          class: Object.const_get(task['type']),
          settings: task.except('type'),
        }
    }
    logger.info("  - #{job_id}: #{tasks[0][:class].name}")

    job = Kiba.parse do
      sources, tasks = tasks.partition{ |task|
        task[:class] <= Source || task[:class] <= Connector
      }

      sources.each{ |src|
        if src[:class] <= Connector
          connector = src
          connector = connector[:class].new(
            job_id,
            connector[:settings],
            source_filter,
            path,
          )
          # Define source()
          # self as Kiba context
          connector.setup(self)
        else
          source(src[:class], job_id, src[:id], nil, src[:class].const_get(:Settings).from_hash(src[:settings]))
        end
      }

      (tasks || []).select{ |task| ![ValidateTransformer].include?(task[:class]) }.each{ |task|
        transform(task[:class], task[:class].const_get(:Settings).from_hash(task[:settings]))
      }
      transform(EndDateTransformer, Transformer::TransformerSettings.from_hash({}))
      transform(MetadataMerge, MetadataMerge::Settings.from_hash({ 'destination_id' => job_id })) # Merge before validate
      transform(SanitizeTagsTransformer, Transformer::TransformerSettings.from_hash({}))
      transform(ValidateTransformer, Transformer::TransformerSettings.from_hash({}))
      transform(RefsIntegrityTransformer, Transformer::TransformerSettings.from_hash({}))
      destination(GeoJson, path)
    end
    Kiba.run(job)
  end
end
