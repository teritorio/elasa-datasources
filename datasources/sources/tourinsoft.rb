# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


class TourinsoftSource < Source
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
    url = "http://wcf.tourinsoft.com/Syndication/3.0/#{client}/#{syndication}/Objects?$format=json"
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    JSON.parse(resp.body)['value']
  end

  def split(string, sub_part = nil)
    parts = string.split('#').compact_blank.uniq
    if !sub_part.nil?
      parts = parts.collect{ |part|
        part.split('|')[sub_part]
      }.compact_blank.uniq
    end
    parts
  end

  def multiple_split(row, fields, sub_part = nil)
    parts = fields.collect{ |i| row[i] }.compact.collect{ |n| n.split('#') }.flatten(1).compact_blank.uniq
    if !sub_part.nil?
      parts = parts.collect{ |value|
        value.split('|')[sub_part]
      }.compact_blank.uniq
    end
    parts
  end

  def each
    super(self.class.fetch(@settings.client, @settings.syndication))
  end

  def map_id(feat)
    feat['SyndicObjectID']
  end

  def map_updated_at(feat)
    feat['Updated']
  end

  def map_native_properties(feat, properties)
    feat.slice(*properties.keys).compact.to_h{ |k, v|
      v = split(v, 0) if properties.dig(k, 'split')
      k = properties[k]['rename'] || k
      [k, v]
    }
  end
end
