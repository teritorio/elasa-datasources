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
require './datasources/transforms/derivated_tag'


class Job
  def initialize(job_id, job, source_filter, path)
    tasks = job.values
    puts "#{job_id}: #{tasks[0]['type']}"
    tasks = tasks.collect{ |task| [Object.const_get(task['type']), task.except('type')] }
    connector = tasks[0]
    tasks = tasks[1..]

    c = connector[0].new(
      job_id,
      c = connector[1]['attribution'],
      c = connector[1].except('attribution', 'type'),
      source_filter,
      path,
    ) { |connector, destination_id, source, *args|
      job = Kiba.parse do
        # Define source()
        # self as Kiba context
        connector.setup(self, source, *args)

        dest = tasks.pop if tasks.size > 0 && tasks[-1][0] <= Destination

        tasks.each{ |classs, settings|
          transform(classs, settings)
        }

        puts path.inspect
        if dest.nil?
          destination(GeoJson, path, destination_id)
        else
          destination(dest[0], path, dest[1])
        end
      end
      Kiba.run(job)
    }
  end
end
