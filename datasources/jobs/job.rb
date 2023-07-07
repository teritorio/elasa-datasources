# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require './datasources/connectors/apidae'
require './datasources/connectors/csv'
require './datasources/connectors/geotrek'
require './datasources/connectors/teritorio_osm'
require './datasources/connectors/tourinsoft_cdt50'
require './datasources/connectors/tourinsoft_sirtaqui'
require './datasources/connectors/tourism_system'
require './datasources/sources/geojson'
require './datasources/destinations/destination'
require './datasources/destinations/geojson_by'
require './datasources/destinations/geojson'
require './datasources/transforms/derivated_tag'
require './datasources/transforms/join'


class Job
  def initialize(job_id, job, source_filter, path)
    tasks = job.values
    puts "#{job_id}: #{tasks[0]['type']}"
    tasks = tasks.collect{ |task| [Object.const_get(task['type']), task.except('type')] }

    if tasks[0][0] <= Connector
      connector = tasks[0]
      tasks = tasks[1..]
      connector[0].new(
        job_id,
        connector[1],
        source_filter,
        path,
      ).each { |connector, destination_id, args|
        job = Kiba.parse do
          # Define source()
          # self as Kiba context
          connector.setup(self, args)
          Job.content(self, tasks, destination_id, path)
        end
        Kiba.run(job)
      }
    else
      job = Kiba.parse do
        sources, tasks = tasks.partition{ |task| task[0] <= Source }
        sources.each{ |src|
          source(src[0], **src[1])
        }
        # self as Kiba context
        Job.content(self, tasks, job_id, path)
      end
      Kiba.run(job)
    end
  end

  def self.content(kiba, tasks, destination_id, path)
    dest = tasks.pop if tasks.size > 0 && tasks[-1][0] <= Destination

    tasks.each{ |classs, settings|
      kiba.transform(classs, settings)
    }

    if dest.nil?
      kiba.destination(GeoJson, path, destination_id)
    else
      kiba.destination(dest[0], path)
    end
  end
end
