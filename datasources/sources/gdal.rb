# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'cgi'
require 'sorbet-runtime'
require_relative 'geojson'


class GdalSource < GeoJsonSource
  class Settings < GeoJsonSource::Settings
    const :gdal_command, String, default: 'ogr2ogr -f GeoJSON {{tmp_geojson}} /vsicurl/{{url}}'
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def fetch(_url)
    Tempfile.open('foo') { |tmp_geojson|
      tmp_geojson.close
      path = T.must(tmp_geojson.path)
      tmp_geojson.unlink
      command = @settings.gdal_command.gsub('{{tmp_geojson}}', path).gsub('{{url}}', @settings.url)
      `#{command}`
      super("file://#{path}")
    }
  end

  def map_id(_feat)
    nil
  end

  def map_updated_at(_feat)
    nil
  end

  def map_source(_feat)
    @settings.attribution
  end
end
