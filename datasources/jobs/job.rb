# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require './datasources/connectors/apidae'
require './datasources/connectors/csv'
require './datasources/connectors/geotrek'
require './datasources/connectors/join'
require './datasources/connectors/overpass'
require './datasources/connectors/tourinsoft_cdt50'
require './datasources/connectors/tourinsoft_sirtaqui'
require './datasources/connectors/tourism_system'
require './datasources/destinations/destination'
require './datasources/destinations/geojson_by'
require './datasources/destinations/geojson'


class Job
  def initialize(job_id, job, source_filter, path)
    tasks = job.values
    puts "#{job_id}: #{tasks[0]['type']}"
    tasks = tasks.collect{ |task| Object.const_get(task['type']) }
    connector = tasks[0]

    c = connector.new(
      job_id,
      job.values[0]['attribution'],
      job.values[0].except('attribution', 'type'),
      source_filter,
      path,
    ) { |connector, source, *args|
      job = Kiba.parse do
        # Define source()
        # self as Kiba context
        connector.setup(self, source, *args)

        if tasks[-1] <= Destination
          # tasks[1..]
          destination(tasks[-1], path)
        else
          # tasks[1..-2]
          destination(GeoJson, job_id, path)
        end
      end
      Kiba.run(job)
    }
  end
end
