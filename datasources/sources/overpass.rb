# frozen_string_literal: true
# typed: true

require 'http'
require 'sorbet-runtime'

require_relative 'source'

class OverpassSource < Source
  extend T::Sig

  class Settings < Source::SourceSettings
    const :attribution, String, default: '<a href="https://www.openstreetmap.org/copyright" target="_blank">© OpenStreetMap contributors</a>', override: true

    const :overpass, String, default: 'https://overpass-api.de/api/interpreter'
    const :query, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def fetch(url)
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    json = JSON.parse(resp.body)
    if !json['remark'].nil?
      raise [url, json['remark']].inspect
    end

    json
  end

  def overpass(overpass_query)
    raw_query = CGI.escape(overpass_query)
    url = "#{@settings.overpass}?data=#{raw_query}"

    fetch(url)['elements']
  end

  def each(&block)
    loop(ENV['NO_DATA'] ? [] : overpass(@settings.query), &block)
  end

  def map_id(feat)
    feat['type'][0] + feat['id'].to_s
  end

  def map_updated_at(feat)
    feat['timestamp'] || feat['tags']['timestamp']
  end

  def map_geometry(feat)
    coordinates = (
      if !feat['lon'].nil?
        [feat['lon'], feat['lat']]
      elsif !feat.dig('center', 'lon').nil?
        [feat['center']['lon'], feat['center']['lat']]
      elsif !feat.dig('tags', 'lon').nil?
        [feat['tags']['lon'].to_f, feat['tags']['lat'].to_f]
      end
    )

    if !coordinates.nil?
      return {
        type: 'Point',
        coordinates: coordinates,
      }
    end

    return if feat['geometry'].nil?

    {
      type: 'LineString',
      coordinates: feat['geometry'].collect{ |g| [g['lon'], g['lat']] },
    }
  end

  def map_tags(feat)
    feat['tags'].except('timestamp', 'lon', 'lat')
  end
end
