# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require './datasources/connectors/apidae'
require './datasources/connectors/csv'
require './datasources/connectors/geotrek'
require './datasources/connectors/overpass'
require './datasources/connectors/teritorio_ontology'
require './datasources/connectors/teritorio_osm'
require './datasources/connectors/tourinsoft_cdt50'
require './datasources/connectors/tourinsoft_sirtaqui'
require './datasources/connectors/tourism_system'
require './datasources/sources/geojson'
require './datasources/destinations/destination'
require './datasources/destinations/geojson'
require './datasources/transforms/derivated_tag'
require './datasources/transforms/end_date'
require './datasources/transforms/join'
require './datasources/transforms/metadata_merge'
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
          tasks = tasks[1..]
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
          source(src[:class], job_id, src[:id], src[:settings])
        end
      }

      tasks_by_class = tasks.to_h{ |task| [task[:class], task[:settings]] }
      (tasks || []).select{ |task| ![ValidateTransformer].include?(task[:class]) }.each{ |task|
        transform(task[:class], task[:settings])
      }
      transform(EndDateTransformer, {})
      transform(MetadataMerge, { 'destination_id' => job_id }) # Merge before validate
      transform(ValidateTransformer, tasks_by_class[ValidateTransformer] || {})
      destination(GeoJson, path)
    end
    Kiba.run(job)
  end
end
