# frozen_string_literal: true
# typed: true

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

    # datas = DatatourismeSource.fetch("#{@settings['flow_key']}/#{@settings['key']}")


    # each(datas) do |data|
    #   destination_id = "#{data['identifier']}-#{data['publisher_name']}"
    #   name = { 'fr' => data['publisher_name'] }

    kiba.source(
      self.class.source_class,
      @job_id,
      @job_id,
      { 'fr' => 'Datatourisme' },
      self.class.source_class.const_get(:Settings).from_hash(@settings.merge({ 'destination_id' => @job_id })),
    )
    # end
  end
end
