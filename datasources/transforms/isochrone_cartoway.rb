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

  @@isochrone_colour = ['#00C500', '#FFAC00']

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

    isochrones.each_with_index.collect{ |(thresold, isochrone), index|
      r = T.cast(Marshal.load(Marshal.dump(row)), Row)
      r[:geometry] = isochrone['geometry']
      r[:properties][:id] += ",#{thresold}"
      r[:properties][:tags] ||= {}
      r[:properties][:tags][:name] = {
        'fr-FR' => "Zone à moins de #{thresold / 60} min en voiture",
        'en-US' => "Zone within #{thresold / 60} min by car",
      }
      r[:properties][:tags][:description] = {
        'fr-FR' => "Calcul de l'accessibilité de tous POI à moins de #{thresold / 60} minutes en voiture.",
        'en-US' => "Calculation of the accessibility of all POIs within #{thresold / 60} minutes by car.",
      }
      r[:properties][:tags][:colour] = @@isochrone_colour[index % @@isochrone_colour.size]
      r[:properties][:natives] ||= {}
      r[:properties][:natives][:isochrones_thresolds] = thresold
      r
    }
  end
end
