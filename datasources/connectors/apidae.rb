# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/apidae'


class Apidae < Connector
  def setup(kiba)
    kiba.source(I18nSource, @job_id, @job_id, { 'url' => 'datasources/connectors/i18n_generator_default.json' })

    projet_id = @settings['projetId']
    api_key = @settings['apiKey']
    selections = ApidaeSource.fetch('referentiel/selections', { apiKey: api_key, projetId: projet_id })

    selections.select{ |selection|
      @source_filter.nil? || selection['nom'].start_with?(@source_filter)
    }.each{ |selection|
      name = "#{selection['id']}-#{selection['nom']}"
      kiba.source(
        ApidaeSource,
        @job_id,
        name,
        @settings.merge({ 'selection_id' => selection['id'] }),
      )
    }
  end
end
