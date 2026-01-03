# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


class GeoJsonTagsNativesSource < Source
  class Settings < Source::SourceSettings
    const :url, String
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  def fetch(url)
    body = (
      if url.start_with?('file://')
        path = url[('file://'.size)..]
        File.file?("internal/#{path}") ? File.read("internal/#{path}") : File.read(path)
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

  def each(&block)
    loop(ENV['NO_DATA'] ? [] : fetch(@settings.url), &block)
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
    feat['properties']['tags'].transform_keys(&:to_sym)
  end

  def map_native_properties(feat, properties)
    natives = feat['properties']['natives']
    natives = natives.slice(*properties) if !natives.nil? && !properties.nil?
    natives
  end

  sig { params(feat: T.untyped).returns(T.nilable(T::Array[T.any(Integer, String)])) }
  def map_refs(feat)
    feat['properties']['refs']
  end
end
