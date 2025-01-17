# frozen_string_literal: true
# typed: true

require 'csv'
require 'http'
require 'iostreams'
require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'


class CsvSource < Source
  class Settings < Source::SourceSettings
    const :url, String
    const :col_sep, String, default: ','
    const :quote_char, String, default: '"'
    const :id, T::Array[String]
    const :lon, String
    const :lat, String
    const :timestamp, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig {
    params(
      url: String,
      col_sep: String,
      quote_char: String,
    ).returns(T::Enumerable[T::Hash[String, String]])
  }
  def fetch(url, col_sep, quote_char)
    reader = IOStreams.path(url)

    Enumerator.new { |yielder|
      header = T.let(nil, T.nilable(T::Array[T.nilable(String)]))
      reader.each{ |line|
        a = CSV.parse_line(line, col_sep: col_sep, quote_char: quote_char)
        if header.nil?
          header = a
        elsif !a.nil?
          yielder << T.must(header).zip(T.must(a)).to_h
        end
      }
    }
  end

  def each(&block)
    loop(ENV['NO_DATA'] ? [] : fetch(@settings.url, @settings.col_sep, @settings.quote_char), &block)
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
