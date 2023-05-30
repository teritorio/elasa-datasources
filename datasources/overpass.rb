# frozen_string_literal: true
# typed: true

require 'yaml'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'

require_relative 'libs/map_osm'
require_relative 'libs/geocode'
require_relative 'datasource'


# module Datasources
class Overpass < Datasource
  def process(_source_id, settings, dir)
    relation_id = settings['relation_id']
    configs = settings['configs']
    attribution = settings['attribution']

    config = configs.inject({}){ |sum, config_path|
      sum.merge(YAML.safe_load(File.read(config_path)))
    }
    FileUtils.makedirs("#{dir}/config")
    generated_config = "#{dir}/config/osm_tags.json"
    File.write(generated_config, JSON.dump(config))

    config.transform_values{ |cat|
      raw = overpass(relation_id, cat['select'])
      ret = map(raw, attribution)
      ret = Geocode.reverse(ret) if cat['georeverse']
      ret
    }
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

  def map(raw, attribution)
    raw.map{ |r|
      {
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: r['lon'].nil? ? [r['center']['lon'], r['center']['lat']] : [r['lon'], r['lat']],
        },
        properties: {
          id: r['type'][0] + r['id'].to_s,
          updated_at: r['timestamp'],
          source: attribution,
          tags: MapOSM.map(r['tags']),
        }
      }
    }
  end
end
# end
