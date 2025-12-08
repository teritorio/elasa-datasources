# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/metadata'
require_relative '../sources/open_agenda'

class OpenAgenda < Connector
  def self.source_class
    OpenAgendaSource
  end

  def setup(kiba)
    kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
      'tags_schema_file' => [
        '../../datasources/schemas/tags/base.schema.json',
        '../../datasources/schemas/tags/event.schema.json',
      ],
      'i18n_file' => [
        '../../datasources/schemas/tags/base.i18n.json',
        '../../datasources/schemas/tags/event.i18n.json',
      ]
    }))

    super
  end
end
