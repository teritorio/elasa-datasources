# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/tourinsoft'


class Tourinsoft < Connector
  def setup(kiba)
    kiba.source(I18nSource, @job_id, @job_id, { 'urls' => [
      'datasources/connectors/i18n-properties-tags.json',
      'datasources/connectors/i18n-properties-tags-event.json',
      'datasources/connectors/i18n-properties-tags-hosting.json',
      'datasources/connectors/i18n-properties-tags-restaurant.json',
      'datasources/connectors/i18n-properties-tags-route.json',
    ] })

    @settings['syndications'].select{ |name, _syndication|
      @source_filter.nil? || name.start_with?(@source_filter)
    }.each{ |name, syndication|
      kiba.source(
        self.class.source_class,
        @job_id,
        name,
        @settings.merge({ 'syndication' => syndication }),
      )
    }
  end
end
