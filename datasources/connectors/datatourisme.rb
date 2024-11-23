# frozen_string_literal: true
# typed: true

require 'async'
require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/datatourisme'
require_relative '../sources/metadata'

class Datatourisme < Connector
  def self.source_class
    DatatourismeSource
  end

  def setup(kiba)
    kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
      'schema' => [
        'datasources/schemas/tags/base.schema.json',
      ],
      'i18n' => [
        'datasources/schemas/tags/base.i18n.json',
      ]
    }))

    DatatourismeSource.fetch("#{@settings['flow_key']}/#{@settings['key']}")
                      .select { |data| @source_filter.nil? || data.dig('type', 'value').start_with?(@source_filter) }
                      .group_by { |h| h.dig('type', 'value') }
                      .map do |key, data|
      Async do
        destination_id = "#{@job_id}-#{key.split('#').last}"
        name = { 'fr' => 'Datatourisme' }

        kiba.source(
          self.class.source_class,
          @job_id,
          destination_id,
          name,
          self.class.source_class::Settings.from_hash(@settings.merge({ 'destination_id' => destination_id, 'datas' => data })),
        )
      end
    end.each(&:wait)
  end
end
