# frozen_string_literal: true
# typed: true

require 'duckdb'
require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'


class DuckdbSource < Source
  class Settings < Source::SourceSettings
    const :query, String
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
      query: String,
    ).returns(T::Enumerable[T::Hash[String, String]])
  }
  def fetch(query)
    db = DuckDB::Database.open
    con = db.connect
    con.query('LOAD httpfs')
    results = con.query(query)
    Enumerator.new { |yielder|
      columns = results.columns.map(&:name)
      results.each do |row|
        yielder << columns.zip(row).to_h
      end
    }
  end

  def each(&block)
    loop(ENV['NO_DATA'] ? [] : fetch(@settings.query), &block)
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
