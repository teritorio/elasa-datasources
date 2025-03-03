# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'cgi'
require 'sorbet-runtime'
require_relative 'gdal'


class GtfsStopSource < GdalSource
  class Settings < GdalSource::Settings
    const :gdal_command, String, default: 'ogr2ogr -f GeoJSON {{tmp_geojson}} -dialect SQLITE -sql "
      SELECT
        stops.*,
        routes.route_color,
        group_concat(DISTINCT routes.route_short_name) AS route_ref,
        group_concat(DISTINCT routes.route_id||\'~\') AS route_ids
      FROM
        stops
        JOIN stop_times ON
          stop_times.stop_id = stops.stop_id
        JOIN trips ON
          trips.trip_id = stop_times.trip_id
        JOIN routes ON
          routes.route_id = trips.route_id
      GROUP BY
        stops.stop_id
    " "/vsicurl_streaming/{{url}}"', override: true
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def map_id(feat)
    feat['properties']['stop_id']
  end

  def map_updated_at(_feat)
    '1970'
  end

  def map_tags(feat)
    r = feat['properties']
    {
      name: { 'fr-FR' => r['stop_name'] }.compact_blank,
      colour: r['route_color'] ? "##{r['route_color']}" : nil,
      'colour:text' => r['route_text_color'] ? "##{r['route_text_color']}" : nil,
      route_ref: r['route_ref'].split(',')
    }
  end

  def map_refs(feat)
    feat['properties']['route_ids']&.[](..-2)&.split('~,')
  end
end
