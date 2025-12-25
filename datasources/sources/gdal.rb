# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'cgi'
require 'sorbet-runtime'
require_relative 'geojson_tags_natives'


class GdalSource < GeoJsonTagsNativesSource
  class Settings < GeoJsonTagsNativesSource::Settings
    const :gdal_command, String, default: 'ogr2ogr -f GeoJSON {{tmp_geojson}} /vsicurl/{{url}}'
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  def fetch(_url)
    Tempfile.open('foo') { |tmp_geojson|
      tmp_geojson.close
      path = T.must(tmp_geojson.path)
      tmp_geojson.unlink

      ext = @settings.url.split('.').last
      Tempfile.open(['foo', ".#{ext}"]) { |temp_input|
        temp_input.write(HTTP.get(@settings.url).body)
        temp_input.close

        command = @settings.gdal_command.gsub('{{tmp_geojson}}', path).gsub('{{temp_input}}', T.must(temp_input.path))
        `#{command}`
        JSON.parse(File.read(path))['features']
      }
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
