# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/geojson'
require_relative '../transforms/join'


class Join < Connector
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    super(multi_source_id, attribution, settings, source_filter, path)

    settings['sources'].each{ |source_url|
      yield [
        self,
        [source(GeoJsonSource, multi_source_id, attribution, { source_url: source_url })]
      ]
    }
  end

  def setup(kiba, params)
    super(kiba, params)
    kiba.transform(JoinTransformer, settings['key'])
  end
end
