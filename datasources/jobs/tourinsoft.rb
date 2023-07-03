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
        tourinsoft_settings = {
          client: settings['client'],
          syndication: syndication,
          website_details_url: settings['website_details_url'],
          photo_base_url: settings['photo_base_url'],
        }
        source(source_class, name, attribution, tourinsoft_settings, path)

        destination(GeoJson, name, path)
      end
      Kiba.run(job)
    }
  end
end
