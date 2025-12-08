# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/tourism_system'


class TourismSystem < Connector
  def setup(kiba)
    kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
      'tags_schema_file' => [
        '../../datasources/schemas/tags/base.schema.json',
        '../../datasources/schemas/tags/event.schema.json',
        '../../datasources/schemas/tags/hosting.schema.json',
        '../../datasources/schemas/tags/restaurant.schema.json',
        '../../datasources/schemas/tags/route.schema.json',
      ],
      'i18n' => [
        '../../datasources/schemas/tags/base.i18n.json',
        '../../datasources/schemas/tags/event.i18n.json',
        '../../datasources/schemas/tags/hosting.i18n.json',
        '../../datasources/schemas/tags/restaurant.i18n.json',
        '../../datasources/schemas/tags/route.i18n.json',
      ]
    }))

    id = @settings['id']
    basic_auth = @settings['basic_auth']
    playlists = @settings['playlists']

    thesaurus_fr = TourismSystemSource.fetch(basic_auth, "/thesaurus/ts/#{id}/tree/fr")
    thesaurus = HashExcep[parse_thesaurus(thesaurus_fr).to_h]

    TourismSystemSource.fetch_data(basic_auth, "/content/ts/#{id}").collect { |playlist|
      [playlist['metadata']['name'], playlist['metadata']['id']]
    }.select{ |name, _id|
      (playlists.blank? || playlists.include?(name)) && (@source_filter.nil? || name.start_with?(@source_filter))
    }.each{ |name, playlist_id|
      tourism_system_settings = @settings.merge({
        'playlist_id' => playlist_id,
        'thesaurus' => thesaurus,
      })
      kiba.source(
        TourismSystemSource,
        @job_id,
        name,
        { 'fr-FR' => name },
        TourismSystemSource::Settings.from_hash(tourism_system_settings),
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
