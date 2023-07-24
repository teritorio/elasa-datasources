# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/overpass_select'
require_relative '../transforms/osm_tags'
require_relative '../transforms/reverse_geocode'


class TeritorioOsm < Connector
  def setup(kiba)
    configs = @settings['configs']
    config = configs.inject({}){ |sum, config_path|
      sum.merge(YAML.safe_load(File.read(config_path)))
    }
    FileUtils.makedirs("#{@path}/config")
    generated_config = "#{@path}/config/osm_tags.json"
    File.write(generated_config, JSON.dump(config))

    config.each{ |source_id, _extra|
      kiba.source(
        OverpassSelectSource,
        @job_id,
        source_id,
        @settings.merge({ 'select' => c['select'] }),
      )
    }

    return unless extra['georeverse']

    kiba.transform(ReverseGeocode)
  end
end
