# frozen_string_literal: true
# typed: true

require 'csv'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'

require_relative 'libs/map_osm'
require_relative 'datasource'


# module Datasources
class CSVSource < Datasource
  def process(source_id, settings, _dir)
    url = settings['url']
    col_sep = settings['col_sep']
    id = settings['id']
    lon = settings['lon']
    lat = settings['lat']
    timestamp = settings['timestamp']
    attribution = settings['attribution']

    raw = fetch(url, col_sep)
    objects = map(raw, id, lon, lat, timestamp, attribution)
    { source_id => objects }
  end

  def fetch(url, col_sep)
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    CSV.parse(resp.body.to_s, headers: true, col_sep: col_sep, quote_char: nil).each(&:to_h)
  end

  def map(raw, id, lon, lat, timestamp, attribution)
    raw.select{ |r|
      r[id].present? && r[lon].present? && r[lat].present?
    }.map{ |r|
      {
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [r[lon].to_f, r[lat].to_f],
        },
        properties: {
          id: r[id].to_i,
          timestamp: r[timestamp],
          source: attribution,
          tags: MapOSM.map(r.to_h.except(id, lon, lat, timestamp).compact_blank, %w[route_ref])
        }.compact_blank
      }
    }
  end
end
# end
