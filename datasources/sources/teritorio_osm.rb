# frozen_string_literal: true
# typed: true

# require 'yaml'
require 'http'
# require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'

class TeritorioOsmSource < Source
  attr_reader :input_file

  def initialize(job_id, destination_id, settings)
    super(job_id, destination_id, settings)
    @relation_id = @settings['relation_id']
    @select = @settings['select']
  end

  def fetch(url)
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    resp.body
  end

  def overpass(relation_id, selectors)
    area_id = 3_600_000_000 + relation_id
    overpass = "
[out:json][timeout:25];
area(#{area_id})->.a;
nwr#{selectors}(area.a);
out center meta;
"
    raw_query = CGI.escape(overpass)
    url = "https://overpass-api.de/api/interpreter?data=#{raw_query}"

    JSON.parse(fetch(url))['elements']
  end

  def each
    super(overpass(@relation_id, @select))
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
