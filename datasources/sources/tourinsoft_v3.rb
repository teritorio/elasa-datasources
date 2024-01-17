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

  def self.fetch(client, syndication)
    url = "https://api-v3.tourinsoft.com/api/syndications/#{client}/#{syndication}?format=json"
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
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
end
