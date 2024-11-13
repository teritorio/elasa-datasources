# frozen_string_literal: true
# typed: false

require 'json'
require 'http'
require 'active_support/all'

require 'jsonpath'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'

class OpenAgendaSource < Source
  # OpenAgendaSource::Settings
  # url for lecture requires an API key, agenda UID

  class Settings < Source::SourceSettings
    const :key, String, name: 'key' # API key
    const :agenda_uid, T.nilable(String), name: 'agendaUid' # Agenda UID
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } }

  def jp(object, path)
    JsonPath.on(object, "$.#{path}")
  end

  def jp_first(object, path)
    jp(object, path)&.first
  end

  def self.build_url(path, query)
    query_string = query.flat_map do |key, value|
      if value.is_a?(Array)
        value.map { |v| "#{CGI.escape(key.to_s)}[]=#{CGI.escape(v.to_s)}" }
      else
        "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
      end
    end.join('&')
    "https://api.openagenda.com/v2/#{path}?#{query_string}"
  end

  def self.fetch(path, query)
    results = T.let([], T::Array[T.untyped])
    after = T.let([], T::Array[Float])
    size = T.let(100, Integer) # max size result per page

    query = query.merge({ after: after, size: size })
    next_url = T.let(build_url(path, query), T.nilable(String))
    while next_url
      response = HTTP.follow.get(next_url)
      raise [url, response].inspect unless response.status.success?

      json = JSON.parse(response.body)
      results += json['agendas']
      after = json['after']
      break if !after

      next_url = T.let(build_url(path, query.merge({ after: after })), T.nilable(String))
    end
    results
  end

  def self.fetch_paged(path, query)
    after = nil
    size = 100 # max size result per page

    query = query.merge({ after: after, size: size })
    next_url = T.let(build_url(path, query), T.nilable(String))

    p next_url
    results = T.let([], T::Array[T.untyped])

    while next_url
      response = HTTP.follow.get(next_url)
      raise [next_url, response].inspect if response.status.success?

      json = JSON.parse(response.body)
      results += json['events']

      after = json['after']
      p after
      break if !after

      next_url = T.let(build_url(path, query.merge({ after: after })), T.nilable(String))
    end
    results
  end

  def self.openning(periode)
    return nil if periode.blank?

    date_start = periode.dig(:firstTiming, :begin)&.[](0..9)
    date_end = periode.dig(:firstTiming, :end)&.[](0..9)
    hour_start = periode.dig(:firstTiming, :begin)&.[](11..15)
    hour_end = periode.dig(:firstTiming, :end)&.[](11..15)

    [date_start, date_end, [hour_start, hour_end].compact.join(' - ')].compact.join(' ')
  end

  def each
    if ENV['NO_DATA']
      super([])
    else
      super(self.class.fetch_paged("agendas/#{@settings.agendaUid}/events", {
        key: @settings.key,
        agenda_uid: @settings.agenda_uid,
        location_uid: @settings.location_uid,
        event_uid: @settings.event_uid
      }))
    end
  end

  def map_id(feat)
    feat['uid']
  end

  def map_updated_at(feat)
    feat['updatedAt']
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat.dig(:location, :latitude),
        feat.dig(:location, :longitude)
      ]
    }
  end

  def map_tags(feat)
    r = feat
    date_start, date_end, hour = self.class.openning(r)

    {
      name: r['title'],
      description: r.dig(:description, :fr),
    }

  end

  def map_native_properties(feat, properties)
    properties.transform_values do |path|
      jp(feat, path)
    end
  end
end
