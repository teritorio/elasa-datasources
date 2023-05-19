# frozen_string_literal: true
# typed: true

require 'csv'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'


# module CSVSource
class CSVSource
  def process(source_id, url, col_sep, id, lon, lat, timestamp, attribution)
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

  @@multiple = %w[route_ref image phone mobile]

  def map(raw, id, lon, lat, timestamp, _attribution)
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
          id: r[id].to_f,
          timestamp: r[timestamp],
          tags: r.to_h.except(id, lon, lat, timestamp).compact_blank.to_h{ |k, v|
            [k, @@multiple.include?(k) ? v.split(';').collect(&:strip) : v]
          }
        }.compact_blank
      }
    }
  end
end
# end
