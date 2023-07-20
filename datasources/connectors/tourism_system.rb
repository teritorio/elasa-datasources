# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/tourism_system'


class TourismSystem < Connector
  def setup(kiba)
    kiba.source(I18nSource, @multi_source_id, { 'url' => 'datasources/connectors/i18n_generator_default.json' })

    id = @settings['id']
    basic_auth = @settings['basic_auth']

    thesaurus_fr = TourismSystemSource.fetch(basic_auth, "/thesaurus/ts/#{id}/tree/fr")
    thesaurus = HashExcep[parse_thesaurus(thesaurus_fr).to_h]

    TourismSystemSource.fetch_data(basic_auth, "/content/ts/#{id}").collect { |playlist|
      [playlist['metadata']['name'], playlist['metadata']['id']]
    }.select{ |name, _id|
      if @source_filter.nil?
        name.start_with?('Teritorio')
      else
        name.start_with?("Teritorio - #{@source_filter}")
      end
    }.each{ |source_id, playlist_id|
      tourism_system_settings = @settings.merge({
        'playlist_id' => playlist_id,
        'thesaurus' => thesaurus,
      })
      kiba.source(
        TourismSystemSource,
        source_id,
        tourism_system_settings,
      )
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
