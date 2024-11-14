# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/open_agenda'
require_relative '../sources/metadata'

class OpenAgenda < Connector
  def setup(kiba)
    kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
      'schema' => [
        'datasources/schemas/tags/base.schema.json',
      ],
      'i18n' => [
        'datasources/schemas/tags/base.i18n.json',
      ]
    }))


    api_key = @settings['key']
    agenda_uid = @settings['agenda_uid'].to_s
    events = OpenAgendaSource.fetch("agendas/#{agenda_uid}/events", {
      key: api_key
    })
    events.each do |event|
      logger.info(event['uid'])
      destination_id = "#{event['uid']}-#{event['title']['fr']}"
      name = event['title']

      kiba.source(
        OpenAgendaSource,
        @job_id,
        destination_id,
        name,
        OpenAgendaSource::Settings.from_hash(@settings.merge({ 'event_uid' => event['uid'].to_s })),
      )
    end
  end
end
