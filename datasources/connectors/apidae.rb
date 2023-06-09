# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/apidae'


class Apidae < Connector
  def each
    projet_id = @settings['projetId']
    api_key = @settings['apiKey']
    selections = ApidaeSource.fetch('referentiel/selections', { apiKey: api_key, projetId: projet_id })

    selections.select{ |selection|
      @source_filter.nil? || selection['nom'].start_with?(@source_filter)
    }.each{ |selection|
      name = "#{selection['id']}-#{selection['nom']}"
      yield [
        ApidaeSource,
        name,
        @settings.merge({ 'selection_id' => selection['id'] }),
      ]
    }
  end
end
