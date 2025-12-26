# frozen_string_literal: true
# typed: true

require 'nokogiri'

require_relative 'transformer'


class GpxTransformer < Transformer
  extend T::Sig
  extend T::Generic

  class Settings < Transformer::TransformerSettings
    const :gpx_cache_duration, Integer, default: 30
  end

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super
    @cache_gpx = Moneta::Adapters::File.new(dir: '/cache-gpx', expires: @settings.gpx_cache_duration)
  end

  sig { params(gpx: String).returns(T.nilable(Hash)) }
  def gpx2geojson(gpx)
    doc = Nokogiri::XML(gpx)
    doc.remove_namespaces!

    coordinates = T.let(doc.xpath('/gpx/rte').collect{ |rte|
      rte.xpath('rtept').collect{ |pt|
        [pt.attribute('lon').to_s.to_f, pt.attribute('lat').to_s.to_f]
      }
    } +
      doc.xpath('/gpx/trk').collect{ |trk|
        trk.xpath('trkseg').collect{ |seg|
          seg.xpath('trkpt').collect{ |pt|
            [pt.attribute('lon').to_s.to_f, pt.attribute('lat').to_s.to_f]
          }
        }
      }.flatten(1), T::Array[T::Array[[Float, Float]]])

    sum = T.let([], T::Array[T::Array[[Float, Float]]])
    coordinates.each{ |linestring|
      # Remove consecutive duplicate points
      linestring = linestring.chunk{ |x| x }.to_a.map(&:first)

      next if linestring.size < 2

      if !sum.empty? && sum[-1][-1] == linestring[0]
        sum[-1] += linestring[1..]
      else
        sum << linestring
      end
    }

    if sum.empty?
      nil
    elsif sum.length == 1
      { type: 'LineString', coordinates: sum[0] }
    else
      { type: 'MultiLineString', coordinates: sum }
    end
  end

  sig { override.params(row: Row).returns(T.untyped) }
  def process_data(row)
    gpx_trace = row.dig(:properties, :tags, :route, :gpx_trace)
    if !gpx_trace.nil?
      gpx_data = (
        if !@cache_gpx.nil? && @cache_gpx.key?(gpx_trace)
          T.cast(@cache_gpx.load(gpx_trace), String)
        else
          resp = HTTP.follow.get(gpx_trace)
          raise [gpx_trace, resp].inspect if !resp.status.success?

          gpx_data = resp.body.to_s
          @cache_gpx&.store(gpx_trace, gpx_data, expires: T.must(@settings.gpx_cache_duration) < 0 ? nil : @settings.cache_duration)
        end
      )

      trace_geojson = gpx2geojson(gpx_data)
      if trace_geojson.nil?
        logger.info("    !     #{row[:properties][:id]} Empty or invalid GPX. Ignore")
        return row
      end
      trace_geos = RGeo::GeoJSON.decode(trace_geojson.to_json)
      if trace_geos.dimension != 1
        logger.info("    !     #{row[:properties][:id]} GPX not a LineString. Ignore")
        return row
      end

      point = RGeo::GeoJSON.decode(row[:geometry].to_json)
      dist = trace_geos.distance(point)
      if dist > 0.02
        logger.info("    !     #{row[:properties][:id]} Point too far away from GPX trace start (#{dist.round(3)} degrees)")
      end

      row[:geometry] = trace_geojson
    end

    row
  end
end
