# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'open-uri'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


class TourinsoftSource < Source
  def initialize(name, attribution, settings, path)
    super(name, attribution, settings, path)
    @name = name
    @client = settings['client']
    @syndication = settings['syndication']
    @website_details_url = settings['website_details_url']
    @photo_base_url = settings['photo_base_url']
  end

  def self.fetch(client, syndication)
    url = "http://wcf.tourinsoft.com/Syndication/3.0/#{client}/#{syndication}/Objects?$format=json"
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    JSON.parse(resp.body)['value']
  end

  def multiple_split(row, fields, sub_part = nil)
    values = fields.collect{ |i| row[i] }.compact.collect{ |n| n.split('#') }.flatten(1).compact_blank.uniq
    if !sub_part.nil?
      values = values.collect{ |value|
        value.split('|')[sub_part]
      }.compact_blank.uniq
    end
    values
  end

  def each
    super(self.class.fetch(@client, @syndication))
  end

  def map_id(feat)
    feat['SyndicObjectID']
  end

  def map_updated_at(feat)
    feat['Updated']
  end
end
