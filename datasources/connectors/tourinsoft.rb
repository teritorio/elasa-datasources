# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/tourinsoft'


class Tourinsoft < Connector
  def setup(kiba)
    kiba.source(MetadataSource, @job_id, nil, nil, MetadataSource::Settings.from_hash({
      'tags_schema_file' => [
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
      ]
    }))

    @settings['syndications'].select{ |name, _syndication|
      @source_filter.nil? || name.start_with?(@source_filter)
    }.each{ |name, syndication|
      # Empty medatadata to force output empty destination
      kiba.source(MockSource, @job_id, nil, nil, MockSource::Settings.from_hash({}))

      kiba.source(
        self.class.source_class,
        @job_id,
        name,
        { 'fr-FR' => name },
        self.class.source_class.const_get(:Settings).from_hash(@settings.merge({ 'syndication' => syndication })),
      )
    }
  end
end
