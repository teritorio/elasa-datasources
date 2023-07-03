# frozen_string_literal: true
# typed: true

# require 'yaml'
require 'http'
# require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'

class OverpassSource < Source
  attr_reader :input_file

  def initialize(source_id, attribution, settings, path)
    super(source_id, attribution, settings, path)
    @relation_id = settings[:relation_id]
    @select = settings[:select]
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
    query = selectors.collect{ |selector|
      s = selector.collect{ |k, v|
        k = k[0] == '~' ? "~\"#{k[1..]}\"" : "\"#{k}\""
        _, o, v = /(=|~=|=~|!=|!~|~)?(.*)/.match(v).to_a
        "[#{k}#{o || '='}\"#{v}\"]"
      }
      "nwr#{s.join}(area.a);"
    }.join("\n")

    ovarpass = "
[out:json][timeout:25];
area(#{area_id})->.a;
(
#{query}
);
out center meta;
"
    raw_query = CGI.escape(ovarpass)
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

  def map_geometry(_feat)
    {
      type: 'Point',
      coordinates: (
        if r['lon'].nil?
          [r['center']['lon'], r['center']['lat']]
        else
          [r['lon'], r['lat']]
        end
      )
    }
  end

  def map_tags(feat)
    feat['tags']
  end
end
