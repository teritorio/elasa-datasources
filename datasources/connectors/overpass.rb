# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/overpass'
require_relative '../transforms/osm_tags'
require_relative '../transforms/reverse_geocode'


class Overpass < Connector
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    super(multi_source_id, attribution, settings, source_filter, path)

    configs = settings['configs']
    config = configs.inject({}){ |sum, config_path|
      sum.merge(YAML.safe_load(File.read(config_path)))
    }
    FileUtils.makedirs("#{path}/config")
    generated_config = "#{path}/config/osm_tags.json"
    File.write(generated_config, JSON.dump(config))

    config.each{ |source_id, c|
      yield [
        self,
        [OverpassSource, source_id, attribution, settings.merge({ 'select' => c['select'] })],
        c
      ]
    }
  end

  def setup(kiba, params, c)
    super(kiba, params)
    kiba.transform(OsmTags)
    return unless c['georeverse']

    kiba.transform(ReverseGeocode)
  end
end
