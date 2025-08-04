# frozen_string_literal: true
# typed: true

require_relative 'transformer'
require 'rgeo/geo_json'


class IsochroneOpenrouteserviceTransformer < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :open_route_service_key, String
    const :profile, String, default: 'driving-car'
    const :type, String, default: 'time'
    const :thresolds, T::Array[Integer]
    const :smoothing, Integer, default: 5
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(coord_x: Float, coord_y: Float).returns(T.untyped) }
  def fetch(coord_x, coord_y)
    url = "https://api.openrouteservice.org/v2/isochrones/#{@settings.profile}"
    resp = HTTP.follow.headers(
      'Authorization' => @settings.open_route_service_key,
      'Content-Type' => 'application/json',
    ).post(url, body: {
      locations: [[coord_x, coord_y]],
      range_type: @settings.type,
      range: @settings.thresolds,
      smoothing: @settings.smoothing,
    }.to_json)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    JSON.parse(resp.body)['features']
  end

  sig { params(data: Source::MetadataRow).returns(T.nilable(Source::MetadataRow)) }
  def process_metadata(data)
    data.data.transform_values { |metadata|
      metadata.with(attribution: '<a href="https://www.openstreetmap.org/copyright" target="_blank">© OpenStreetMap contributors</a>')
    }
    data
  end

  def process_data(row)
    geo = RGeo::GeoJSON.decode(row[:geometry].to_json)
    return nil if geo.nil?

    point = (
      case geo.dimension
      when 0 then geo
      when 1 then geo.point_n(geo.points / 2)
      when 2 then geo.point_on_surface
      else raise "Unsupported dimension: #{geo.dimension}"
      end
    )
    isochrones = fetch(point.x, point.y)
    return nil if isochrones.nil?

    isochrones.collect{ |isochrone|
      row = T.cast(Marshal.load(Marshal.dump(row)), Row)
      row[:geometry] = isochrone['geometry']
      row[:properties][:natives] ||= {}
      row[:properties][:natives][:isochrones_thresolds] = isochrone['properties']['value']
      row
    }
  end
end
