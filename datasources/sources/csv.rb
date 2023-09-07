# frozen_string_literal: true
# typed: true

require 'csv'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'


class CsvSource < Source
  class Settings < Source::SourceSettings
    const :url, String
    const :col_sep, String
    const :id, String
    const :lon, String
    const :lat, String
    const :timestamp, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def fetch(url, col_sep)
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    CSV.parse(resp.body.to_s, headers: true, col_sep: col_sep, quote_char: nil).each(&:to_h)
  end

  def each
    super(fetch(@settings.url, @settings.col_sep))
  end

  def map_id(feat)
    feat[@settings.id].to_i
  end

  def map_updated_at(feat)
    feat[@settings.timestamp]
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat[@settings.lon].to_f,
        feat[@settings.lat].to_f
      ]
    }
  end

  def map_tags(feat)
    feat.to_h.except(@settings.id, @settings.lon, @settings.lat, @settings.timestamp)
  end
end
