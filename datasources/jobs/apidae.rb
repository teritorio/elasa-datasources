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

    selections.group_by{ |selection|
      selection['nom']
    }.each{ |name, selection_by_name|
      job = Kiba.parse do
        selection_by_name.each{ |selection|
          apidea_settings = {
            'projetId' => settings['projetId'],
            'apiKey' => settings['apiKey'],
            'selection_id' => selection['id'],
            'website_details_url' => settings['website_details_url']
          }
          source(ApidaeSource, name, attribution, apidea_settings, path)
        }

        destination(GeoJson, name, path)
      end
      Kiba.run(job)
    }
  end
end
