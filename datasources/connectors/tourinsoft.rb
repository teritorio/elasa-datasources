# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/tourinsoft'


class Tourinsoft < Connector
  def setup(kiba)
    kiba.source(I18nSource, @job_id, @job_id, { 'urls' => [
      'datasources/schemas/tags/base.i18n.json',
      'datasources/schemas/tags/event.i18n.json',
      'datasources/schemas/tags/hosting.i18n.json',
      'datasources/schemas/tags/restaurant.i18n.json',
      'datasources/schemas/tags/route.i18n.json',
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
