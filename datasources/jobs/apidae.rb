# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/apidae'
require_relative '../destinations/geojson'


class Apidae < Job
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    super(multi_source_id, attribution, settings, source_filter, path)

    projet_id = settings['projetId']
    api_key = settings['apiKey']
    selections = ApidaeSource.fetch('referentiel/selections', { apiKey: api_key, projetId: projet_id })

    selections.select{ |selection|
      source_filter.nil? || selection['nom'].start_with?(source_filter)
    }.each{ |selection|
      name = "#{selection['id']}-#{selection['nom']}"
      job = Kiba.parse do
        source(ApidaeSource, name, attribution, settings, path)

        destination(GeoJson, name, path)
      end
      Kiba.run(job)
    }
  end
end
