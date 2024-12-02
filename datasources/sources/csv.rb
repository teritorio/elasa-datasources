# frozen_string_literal: true
# typed: true

require 'csv'
require 'http'
require 'bzip2/ffi'
require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'


class CsvSource < Source
  class Settings < Source::SourceSettings
    const :url, String
    const :uncompress, T.nilable(String)
    const :col_sep, String, default: ','
    const :quote_char, String, default: '"'
    const :id, T::Array[String]
    const :lon, String
    const :lat, String
    const :timestamp, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def fetch(url, col_sep, quote_char)
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    reader = resp.body.to_s
    if @settings.uncompress == 'bz2'
      reader = Bzip2::FFI::Reader.read(StringIO.new(reader))
    end

    CSV.parse(reader, headers: true, col_sep: col_sep, quote_char: quote_char).each(&:to_h)
  end

  def each
    super(ENV['NO_DATA'] ? [] : fetch(@settings.url, @settings.col_sep, @settings.quote_char))
  end

  def map_id(feat)
    @settings.id.collect{ |id| feat[id] }.join(',')
  end

  def map_updated_at(feat)
    feat[@settings.timestamp] || '1970-01-01'
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
