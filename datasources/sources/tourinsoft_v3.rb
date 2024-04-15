# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


class TourinsoftV3Source < Source
  extend T::Sig
  extend T::Helpers
  abstract!

  class Settings < Source::SourceSettings
    const :client, String
    const :syndication, String
    const :website_details_url, T.nilable(String)
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def jp(object, path)
    JsonPath.on(object, "$.#{path}")
  end

  def self.fetch(client, syndication)
    url = "https://api-v3.tourinsoft.com/api/syndications/#{client}/#{syndication}?format=json"
    resp = HTTP.follow.get(url)

    retry_request = T.let(true, T::Boolean)
    while retry_request
      if resp.status.code == 429 # Too Many Requests, Caching in progress
        logger.error('429 # Too Many Requests, Caching in progress ----- SKIP')
        return {} # FIXME: Response is cached server and cannot get a valid one. For now, just skip it
        wait = resp.headers['Retry-After']&.to_i || 60
        logger.info("Too Many Requests, wait for #{wait}")
        sleep(wait + 2) # Wait a bit more to be sure
        retry_request = true
      elsif !resp.status.success?
        raise [url, resp].inspect
      else
        retry_request = false
      end
    end

    JSON.parse(resp.body)['value']
  end

  def each
    super(ENV['NO_DATA'] ? [] : self.class.fetch(@settings.client, @settings.syndication))
  end

  def map_id(feat)
    feat['SyndicObjectID']
  end

  def map_updated_at(feat)
    feat['Updated']
  end

  def map_native_properties(feat, properties)
    properties.transform_values{ |path|
      jp(feat, path)
    }.compact_blank
  end
end
