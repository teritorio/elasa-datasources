# frozen_string_literal: true
# typed: true

# require 'yaml'
require 'http'
# require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'

class OverpassSource < Source
  def fetch(url)
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    resp.body
  end

  def overpass(overpass_query)
    raw_query = CGI.escape(overpass_query)
    url = "https://overpass-api.de/api/interpreter?data=#{raw_query}"

    JSON.parse(fetch(url))['elements']
  end

  def each
    super(overpass(@settings['query']))
  end

  def map_id(feat)
    feat['type'][0] + feat['id'].to_s
  end

  def map_updated_at(feat)
    feat['timestamp']
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: (
        if feat['lon'].nil?
          [feat['center']['lon'], feat['center']['lat']]
        else
          [feat['lon'], feat['lat']]
        end
      )
    }
  end

  def map_tags(feat)
    feat['tags']
  end
end
