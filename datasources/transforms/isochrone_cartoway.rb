# frozen_string_literal: true
# typed: true

require_relative 'transformer'
require 'rgeo/geo_json'


class IsochroneCartowayTransformer < Transformer
  extend T::Sig
  class Settings < Transformer::TransformerSettings
    const :service_key, String
    const :profile, String, default: 'car'
    const :type, String, default: 'time'
    const :thresolds, T::Array[Integer]
    const :smoothing, Integer, default: 5
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(coord_x: Float, coord_y: Float).returns(T.untyped) }
  def fetch(coord_x, coord_y)
    @settings.thresolds.to_h{ |thresold|
      url = "https://router.cartoway.com/0.1/isoline?api_key=#{@settings.service_key}&loc=#{coord_y},#{coord_x}&mode=#{@settings.profile}&dimension=#{@settings.type}&size=#{thresold}"
      resp = HTTP.follow.get(url)
      raise [url, resp].inspect if !resp.status.success?

      [thresold, JSON.parse(resp.body)['features'][0]]
    }
  end

  sig { params(data: Source::MetadataRow).returns(T.nilable(Source::MetadataRow)) }
  def process_metadata(data)
    data.data.transform_values { |metadata|
      metadata.with(attribution: '<a href="https://www.openstreetmap.org/copyright" target="_blank">© OpenStreetMap contributors</a>')
    }
    data
  end

  @@isochrone_name = HashExcep[{
    900 => 'Accessibilité 15 minutes',
    1800 => 'Accessibilité 30 minutes',
  }]

  @@isochrone_description = HashExcep[{
    900 => 'Calcul de l\'accessibilité de chaque POI à 15 minutes',
    1800 => 'Calcul de l\'accessibilité de chaque POI à 30 minutes',
  }]

  @@isochrone_colour = HashExcep[{
    900 => '#00C500',
    1800 => '#FFAC00',
  }]

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

    isochrones.collect{ |thresold, isochrone|
      r = T.cast(Marshal.load(Marshal.dump(row)), Row)
      r[:geometry] = isochrone['geometry']
      r[:properties][:id] += ",#{thresold}"
      r[:properties][:tags] ||= {}
      r[:properties][:tags][:name] = { 'fr-FR' => @@isochrone_name[thresold] }
      r[:properties][:tags][:description] = { 'fr-FR' => @@isochrone_description[thresold] }
      r[:properties][:tags][:colour] = @@isochrone_colour[thresold]
      r[:properties][:natives] ||= {}
      r[:properties][:natives][:isochrones_thresolds] = thresold
      r
    }
  end
end
