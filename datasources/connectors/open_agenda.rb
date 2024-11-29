# frozen_string_literal: true
# typed: true

require 'async'
require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/metadata'
require_relative '../sources/open_agenda'

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

    agenda_uid = @settings['agenda_uid'].to_s
    if agenda_uid.empty?
      agendas = OpenAgendaSource.fetch('agendas', {
        key: @settings['key']
      }, 'agendas')
      agendas.map do |agenda|
        agenda_uid = agenda['uid']
        _call(kiba, agenda_uid)
      end
    else
      _call(kiba, agenda_uid)
    end
  end

  def _call(kiba, agenda_uid)
    @settings['agenda_uid'] = agenda_uid
    events = OpenAgendaSource.fetch("agendas/#{agenda_uid}/events", {
      key: @settings['key'],
      'timings[gte]' => Date.today,
    })

    events.map do |event|
      Async do
        destination_id = "#{agenda_uid}-#{event['uid']}-#{event['title']['fr']}"
        name = event['title']

        kiba.source(
          OpenAgendaSource,
          @job_id,
          destination_id,
          name,
          OpenAgendaSource::Settings.from_hash(@settings.merge({ 'event_uid' => event['uid'].to_s, 'agenda_uid' => agenda_uid })),
        )
      end
    end.each(&:wait)
  end
end
