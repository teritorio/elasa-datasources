# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/apidae'
require_relative '../destinations/geojson'


class Apidae < Job
  def initialize(multi_source_id, attribution, settings, path)
    super(multi_source_id, attribution, settings, path)

    projet_id = settings['projetId']
    api_key = settings['apiKey']
    selections = ApidaeSource.fetch('referentiel/selections', { apiKey: api_key, projetId: projet_id })

    selections.each{ |selection|
      job = Kiba.parse do
        apidea_settings = {
          'projetId' => settings['projetId'],
          'apiKey' => settings['apiKey'],
          'selection_id' => selection['id'],
        }
        source(ApidaeSource, selection['nom'], attribution, apidea_settings, path)
        destination(GeoJson, selection['nom'], path)
      end
      Kiba.run(job)
    }
  end
end
