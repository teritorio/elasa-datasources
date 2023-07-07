# frozen_string_literal: true
# typed: true

require 'csv'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'


class CsvSource < Source
  def initialize(destination_id, settings)
    super(destination_id, settings)
    @url = @settings['url']
    @col_sep = @settings['col_sep']
    @id = @settings['id']
    @lon = @settings['lon']
    @lat = @settings['lat']
    @timestamp = @settings['timestamp']
  end

  def fetch(url, col_sep)
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    CSV.parse(resp.body.to_s, headers: true, col_sep: col_sep, quote_char: nil).each(&:to_h)
  end

  def each
    super(fetch(@url, @col_sep))
  end

  def map_id(feat)
    feat[@id].to_i
  end

  def map_updated_at(feat)
    feat[@timestamp]
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat[@lon].to_f,
        feat[@lat].to_f
      ]
    }
  end

  def map_tags(feat)
    feat.to_h.except(@id, @lon, @lat, @timestamp)
  end
end
