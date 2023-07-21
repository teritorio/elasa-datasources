# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/geotrek'


class Geotrek < Connector
  def self.source_class
    GeotrekSource
  end

  def setup(kiba)
    kiba.source(I18nSource, @job_id, @job_id, { 'urls' => [
      'datasources/connectors/i18n-properties-tags.json',
      'datasources/connectors/i18n-properties-tags-event.json',
      'datasources/connectors/i18n-properties-tags-hosting.json',
      'datasources/connectors/i18n-properties-tags-restaurant.json',
      'datasources/connectors/i18n-properties-tags-route.json',
    ] })
    super(kiba)
  end
end
