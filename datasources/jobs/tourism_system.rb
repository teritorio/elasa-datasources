# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/tourism_system'
require_relative '../destinations/geojson'


class TourismSystem < Job
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    super(multi_source_id, attribution, settings, source_filter, path)

    id = settings['id']
    basic_auth = settings['basic_auth']

    thesaurus_fr = TourismSystemSource.fetch(basic_auth, "/thesaurus/ts/#{id}/tree/fr")
    thesaurus = HashExcep[parse_thesaurus(thesaurus_fr).to_h]

    TourismSystemSource.fetch_data(basic_auth, "/content/ts/#{id}").collect { |playlist|
      [playlist['metadata']['name'], playlist['metadata']['id']]
    }.select{ |name, _id|
      if source_filter.nil?
        name.start_with?('Teritorio')
      else
        name.start_with?("Teritorio - #{source_filter}")
      end
    }.each{ |source_id, playlist_id|
      job = Kiba.parse do
        tourism_system_settings = settings.merge({
          'playlist_id' => playlist_id,
          'thesaurus' => thesaurus,
        })
        source(TourismSystemSource, source_id, attribution, tourism_system_settings, path)
        destination(GeoJson, source_id, path)
      end
      Kiba.run(job)
    }
  end

  def parse_thesaurus(thesaurus)
    thesaurus.collect{ |sub|
      [[sub['key'], sub['label']]] + (
         sub.key?('children') ? parse_thesaurus(sub['children']) : []
       )
    }.flatten(1)
  end
end
