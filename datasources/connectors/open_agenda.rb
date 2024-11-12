# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/open_agenda'

class OpenAgenda < Connector
  def setup(kiba)
    kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
      'schema' => [
        'datasources/schemas/tags/base.schema.json',
        'datasources/schemas/tags/event.schema.json',
        'datasources/schemas/tags/hosting.schema.json',
        'datasources/schemas/tags/restaurant.schema.json',
        'datasources/schemas/tags/route.schema.json',
      ],
      'i18n' => [
        'datasources/schemas/tags/base.i18n.json',
        'datasources/schemas/tags/event.i18n.json',
        'datasources/schemas/tags/hosting.i18n.json',
        'datasources/schemas/tags/restaurant.i18n.json',
        'datasources/schemas/tags/route.i18n.json',
      ],
    }))

    api_key = @settings['key']
    agendas = OpenAgendaSource.fetch('/agendas', { key: api_key })
    agendas.select { |agenda|
      @source_filter.nil? || agenda['title'].start_with?(@source_filter)
    }.each { |agenda|
      destination_id = "#{agenda['uid']}-#{agenda['slug']}"
      name = agenda['title'].transform_keys{ |key| key[('libelle'.size)..].downcase }
      agenda_uid = agenda['uid']

      kiba.source(
        OpenAgendaSource,
        @job_id,
        destination_id,
        name,
        OpenAgendaSource::Settings.from_hash(@settings.merge({ 'agenda_uid' => agenda_uid })),
      )
    }
  end
end
