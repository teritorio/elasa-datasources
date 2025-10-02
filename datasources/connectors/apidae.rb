# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/apidae'


class Apidae < Connector
  def slugify(str)
    s = str
    s = s.gsub(/\s+/, ' ')
    s.strip!
    s.gsub!(' ', '-')
    s.gsub!('&', 'and')
    s = I18n.transliterate(s)
    s.gsub!(/[^\w-]/u, '')
    s.gsub!(/-+/, '-')
    s.mb_chars.downcase.to_s
  end

  def setup(kiba)
    source_filter = @settings['filter']

    kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
      'schema' => [
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
      ],
    }))

    projet_id = @settings['projetId']
    api_key = @settings['apiKey']
    selections = ApidaeSource.fetch('referentiel/selections', { apiKey: api_key, projetId: projet_id })

    selections.select{ |selection|
      (source_filter.nil? || selection['nom'].start_with?(source_filter)) &&
        (@source_filter.nil? || selection['nom'].start_with?(@source_filter))
    }.each{ |selection|
      destination_id = "#{selection['id']}-#{slugify(selection['nom'])}"
      name = { 'fr-FR' => selection['libelle'].transform_keys{ |key| key[('libelle'.size)..].downcase }['fr'] }

      kiba.source(
        ApidaeSource,
        @job_id,
        destination_id,
        name,
        ApidaeSource::Settings.from_hash(@settings.merge({ 'selection_id' => selection['id'] })),
      )
    }
  end
end
