# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


class GeoJsonSource < Source
  class Settings < Source::SourceSettings
    const :url, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def fetch(url)
    body = (
      if url.start_with?('file://')
        File.read(url[('file://'.size)..])
      else
        resp = HTTP.follow.get(url)
        if !resp.status.success?
          raise [url, resp].inspect
        end

        resp.body
      end
    )

    JSON.parse(body)['features']
  end

  def each
    super(ENV['NO_DATA'] ? [] : fetch(@settings.url))
  end

  def map_id(feat)
    feat['properties']['id']
  end

  def map_updated_at(feat)
    feat['properties']['updated_at']
  end

  def map_source(feat)
    feat['properties']['source']
  end

  def map_geometry(feat)
    feat['geometry']
  end

  def map_tags(feat)
    feat['properties']['tags']
  end

  def map_native_properties(feat, properties)
    feat['properties']['natives']
  end
end
