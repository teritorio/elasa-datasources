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
    kiba.source(I18nSource, @job_id, @job_id, { 'url' => 'datasources/connectors/i18n_generator_default.json' })
    super(kiba)
  end
end
