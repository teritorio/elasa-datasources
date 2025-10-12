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
    const :url_options, T.nilable([String, T::Hash[String, T.untyped]])
    const :col_sep, String, default: ','
    const :quote_char, String, default: '"'
    const :nil_value, String, default: ''
    const :id, T::Array[String]
    const :lon, T.nilable(String)
    const :lat, T.nilable(String)
    const :timestamp, String
    const :properties, String, default: 'natives'
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig {
    params(
      url: String,
      url_options: T.nilable([String, T::Hash[String, T.untyped]]),
      col_sep: String,
      quote_char: String,
      nil_value: String,
    ).returns(T::Enumerable[T::Hash[String, String]])
  }
  def fetch(url, url_options, col_sep, quote_char, nil_value)
    reader = IOStreams.path(url)
    reader.stream(url_options[0].to_sym, **url_options[1].transform_keys(&:to_sym)) if !url_options.nil?

    Enumerator.new { |yielder|
      header = T.let(nil, T.nilable(T::Array[T.nilable(String)]))
      reader.each{ |line|
        line = line.force_encoding('utf-8')
        a = CSV.parse_line(line, col_sep: col_sep, quote_char: quote_char, nil_value: nil_value)
        if header.nil?
          header = a
        elsif !a.nil?
          yielder << T.must(header).zip(T.must(a)).to_h
        end
      }
    }
  end

  def each(&block)
    loop(ENV['NO_DATA'] ? [] : fetch(@settings.url, @settings.url_options, @settings.col_sep, @settings.quote_char, @settings.nil_value), &block)
  end

  def map_id(feat)
    @settings.id.collect{ |id| feat[id] }.join(',')
  end

  def map_updated_at(feat)
    feat[@settings.timestamp] || '1970-01-01'
  end

  def map_geometry(feat)
    return if feat[@settings.lon].blank? || feat[@settings.lat].blank?

    {
      type: 'Point',
      coordinates: [
        feat[@settings.lon].to_f,
        feat[@settings.lat].to_f
      ]
    }
  end

  def map_tags(feat)
    return unless @settings.properties == 'tags'

    feat.to_h.except(@settings.id, @settings.lon, @settings.lat, @settings.timestamp)
  end

  def map_native_properties(feat, _properties)
    return unless @settings.properties == 'natives'

    feat.to_h.except(@settings.id, @settings.lon, @settings.lat, @settings.timestamp)
  end
end
