# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/tourinsoft'
require_relative '../destinations/geojson'


class Tourinsoft < Job
  def initialize(source_class, multi_source_id, attribution, settings, source_filter, path)
    super(multi_source_id, attribution, settings, source_filter, path)

    settings['syndications'].select{ |name, _syndication|
      source_filter.nil? || name.start_with?(source_filter)
    }.each{ |name, syndication|
      job = Kiba.parse do
        source(source_class, name, attribution, settings.merge({ 'syndication' => syndication }), path)

        destination(GeoJson, name, path)
      end
      Kiba.run(job)
    }
  end
end
