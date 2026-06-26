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
    const :has_steps, T::Boolean, default: true
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  def jp(object, path)
    JsonPath.on(object, "$.#{path}")&.compact_blank
  end

  def jp_first(object, path)
    jp(object, path)&.first
  end

  def self.fetch(client, syndication)
    url = "https://api-v3.tourinsoft.com/api/syndications/#{client}/#{syndication}?format=json"
    resp = HTTP.follow.get(url)

    retry_request = T.let(true, T::Boolean)
    while retry_request
      if resp.status.code == 429 # Too Many Requests, Caching in progress
        logger.error('429 # Too Many Requests, Caching in progress ----- SKIP')
        return {} # FIXME: Response is cached server and cannot get a valid one. For now, just skip it
        # wait = resp.headers['Retry-After']&.to_i || 60
        # logger.info("Too Many Requests, wait for #{wait}")
        # sleep(wait + 2) # Wait a bit more to be sure
        # retry_request = true
      elsif !resp.status.success?
        raise [url, resp].inspect
      else
        retry_request = false
      end
    end

    JSON.parse(resp.body)['value']
  end

  sig { params(_feature: T.untyped).returns(T::Array[T.untyped]) }
  def extract_steps_from_feature(_feature)
    []
  end

  def features
    @features_cache ||= self.class.fetch(@settings.client, @settings.syndication).collect{ |feat| [:feature, feat] }
    @features_cache
  end

  sig { returns(T::Array[MetadataRow]) }
  def metadatas
    super + (@settings.has_steps ? [
      MetadataRow.new({
        data: {
          "#{@destination_id}-steps" => Metadata.from_hash({
            'name' => { 'en-US' => "#{@destination_id}-steps" },
            'attribution' => @settings.attribution,
            'report_issue' => @settings.report_issue&.serialize,
          })
        }.compact_blank
      })
    ] : [])
  end

  def map_destination_id(type_feat)
    type, _feat = type_feat
    if type == :step
      "#{@destination_id}-steps"
    else
      @destination_id
    end
  end

  def loop(raw = [], &block)
    super(ENV['NO_DATA'] ?
      [] :
      raw.empty? ? self.class.fetch(@settings.client, @settings.syndication).collect{ |feat| [:feature, feat] } :
        raw,
      &block
    )
  end

  def each(&block)
    if ENV['NO_DATA']
      loop([], &block)
    elsif @settings.has_steps
      features_steps = features.collect { |feature|
        feature_steps = extract_steps_from_feature(feature.last)
        feature.last['step_ids'] = feature_steps.pluck('SyndicObjectID')
        [feature] + feature_steps.collect{ |feat| [:step, feat] }
      }.flatten(1)
      loop(features_steps, &block)
    else
      features = self.class.fetch(@settings.client, @settings.syndication).collect{ |feat| [:feature, feat] }
      loop(features, &block)
    end
  end

  def map_id(feat)
    feat.last['SyndicObjectID']
  end

  def map_updated_at(feat)
    feat.last['Updated']
  end

  def map_native_properties(feat, properties)
    (properties || {}).transform_values{ |path|
      jp(feat.last, path)
    }.compact_blank
  end

  def map_tags(type_feat)
    type, feat = type_feat
    type == :feature ? map_feature_tags(feat) : nil
  end

  sig { params(feat: T.untyped).returns(T.untyped) }
  def map_feature_tags(feat); end
end
