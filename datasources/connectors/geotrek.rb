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
      'datasources/schemas/tags/base.i18n.json',
      'datasources/schemas/tags/event.i18n.json',
      'datasources/schemas/tags/hosting.i18n.json',
      'datasources/schemas/tags/restaurant.i18n.json',
      'datasources/schemas/tags/route.i18n.json',
    ] })
    super(kiba)
  end
end
