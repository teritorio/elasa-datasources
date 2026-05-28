# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'uri'
require 'active_support/all'

require 'sorbet-runtime'

require_relative 'source'


class GristSource < Source
  class Settings < Source::SourceSettings
    const :api_url, String
    const :doc_id, String
    const :table_id, String
    const :filter, T.nilable(String)
    const :lat, String
    const :lon, String
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig {
    params(
      url: String,
    ).returns(T::Hash[String, T::Array[T::Hash[String, T.untyped]]])
  }
  def fetch(url)
    body = (
      resp = HTTP.follow.get(url)
      if !resp.status.success?
        raise [url, resp].inspect
      end

      resp.body
    )

    JSON.parse(body)
  end

  sig {
    params(
      api_url: String,
      doc_id: String,
      table_id: String,
    ).returns(T::Array[T::Hash[String, T.untyped]])
  }
  def fetch_column(api_url, doc_id, table_id)
    url = "#{api_url}/docs/#{doc_id}/tables/#{table_id}/columns"
    T.must(fetch(url)['columns'])
  end

  sig {
    params(
      api_url: String,
      doc_id: String,
      table_id: String,
      filter: T.nilable(String),
    ).returns(T::Array[T::Hash[String, T.untyped]])
  }
  def fetch_records(api_url, doc_id, table_id, filter = nil)
    url = "#{api_url}/docs/#{doc_id}/tables/#{table_id}/records"
    url += "?filter=#{URI.encode_www_form_component(filter)}" if filter.present?
    T.must(fetch(url)['records'])
  end

  # JSON Schema types
  TYPE_MAP = {
    'Text' => 'string',
    'Numeric' => 'number',
    'Date' => 'string',
    'DateTime' => 'string',
    'Boolean' => 'boolean',
  }.freeze

  sig { returns(SchemaRow) }
  def schema
    schema = {
      'type' => 'object',
      'properties' => {}
    }
    i18n = {}
    fetch_column(@settings.api_url, @settings.doc_id, @settings.table_id).each{ |column|
      id = column.dig('fields', 'label') || column['id']
      schema['properties'][id] = {
        'type' => TYPE_MAP[column['fields']['type']] || 'string',
        'format' => column['fields']['type'] == 'Date' ? 'date' : (column['fields']['type'] == 'DateTime' ? 'date-time' : nil),
      }
      i18n[id] = {
        '@default' => {
          'en-US' => id
        }.compact_blank,
      }
    }
    SchemaRow.new(
      destination_id: @destination_id,
      natives_schema: JsonSchema.new(schema),
      i18n: i18n,
    )
  end

  def each(&block)
    loop(ENV['NO_DATA'] ? [] : fetch_records(@settings.api_url, @settings.doc_id, @settings.table_id), &block)
  end

  def map_id(feat)
    feat['id']
  end

  def map_updated_at(_feat)
    '1970-01-01'
  end

  def map_geometry(feat)
    return if feat['fields'][@settings.lon].blank? || feat['fields'][@settings.lat].blank?

    {
      type: 'Point',
      coordinates: [
        feat['fields'][@settings.lon].to_f,
        feat['fields'][@settings.lat].to_f
      ]
    }
  end

  def map_native_properties(feat, _properties)
    f = feat['fields'].except(@settings.lat, @settings.lon).compact_blank
    puts f.inspect
    f
  end
end
