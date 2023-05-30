# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'

require 'sorbet-runtime'

require_relative 'job'
require_relative '../sources/overpass'
require_relative '../transforms/osm_tags'
require_relative '../transforms/reverse_geocode'
require_relative '../destinations/geojson'


class Overpass < Job
  def initialize(multi_source_id, attribution, settings, path)
    super(multi_source_id, attribution, settings, path)

    configs = settings['configs']
    config = configs.inject({}){ |sum, config_path|
      sum.merge(YAML.safe_load(File.read(config_path)))
    }
    FileUtils.makedirs("#{path}/config")
    generated_config = "#{path}/config/osm_tags.json"
    File.write(generated_config, JSON.dump(config))

    config.each{ |source_id, c|
      job = Kiba.parse do
        overpass_seting = { relation_id: settings['relation_id'], select: c['select'] }
        source(OverpassSource, source_id, attribution, overpass_seting, path)

        transform(OsmTags)
        if c['georeverse']
          transform(ReverseGeocode)
        end

        destination(GeoJson, source_id, path)
      end
      Kiba.run(job)
    }
  end
end
