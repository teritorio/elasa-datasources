# frozen_string_literal: true
# typed: false

require 'json'
require 'http'
require 'active_support/all'


require 'jsonpath'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'
require_relative 'open_agenda_mixin'

class OpenAgendaSource < Source
  # OpenAgendaSource::Settings
  # url for lecture requires an API key, agenda UID
  include OpenAgendaMixin

  class Settings < Source::SourceSettings
    const :key, String, name: 'key' # API key
    const :agenda_uid, T.nilable(String), name: 'agenda_uid' # Agenda UID
    const :event_uid, T.nilable(String), name: 'event_uid' # Event UID
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

    after = []
    size = 100 # max size result per page

    query = query.merge({ after: after, size: size })
    next_url = T.let(build_url(path, query), T.nilable(String))

    while next_url
      response = HTTP.follow.get(next_url)
      raise [next_url, response].inspect unless response.status.success?

      json = JSON.parse(response.body)

      results += json['events']

      after = json['after']
      break if !after

      next_url = T.let(build_url(path, query.merge({ after: after })), T.nilable(String))
    end
    results
  end

  def self.fetch_event(path, query)
    url = T.let(build_url(path, query), T.nilable(String))
    response = HTTP.follow.get(url)
    raise [url, response].inspect unless response.status.success?

    [JSON.parse(response.body)['event']]
  end

  def openning(periode)
    return nil if periode.blank?

    date_start = jp_first(periode, 'firstTiming.begin')&.[](0..9)
    date_end = jp_first(periode, 'firstTiming.end')&.[](0..9)
    hour_start = jp_first(periode, 'firstTiming.begin')&.[](11..15)
    hour_end = jp_first(periode, 'firstTiming.end')&.[](11..15)

    logger.info([date_start, date_end, [hour_start, hour_end].compact.join(' - ')])

    [date_start, date_end, [hour_start, hour_end].compact.join(' - ')]
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
        jp_first(feat, 'location.latitude').to_f,
        jp_first(feat, 'location.longitude').to_f
      ],
    }
  end

  sig { returns(SchemaRow) }
  def schema
    super.with(
      i18n: {
        'long_description' => {
          '@default' => {
            'fr' => 'Description longue'
          }
        },
      }.merge(OpenAgendaMixin::I18N_IMPAIREMENT),
      schema: {
        'properties' => {
          'long_description' => {
            '$ref' => '#/$defs/multilingual',
          },
        }.merge(OpenAgendaMixin::SCHEMA_IMPAIREMENT),
      }
    )
  end

  def map_tags(feat)
    r = feat
    date_start, date_end, hour = openning(r)

    {
      name: jp_first(r, 'title'),
      description: jp_first(r, 'description'),
      long_description: jp_first(r, 'longDescription'),
      addr: {
        street: jp_first(r, 'location.address'),
        postcode: jp_first(r, 'location.postalCode'),
        city: jp_first(r, 'location.city'),
        country: jp_first(r, 'country.fr') || jp_first(r, 'location.countryCode'),
      },
      website: [jp_first(r, 'location.website').to_s, jp_first(r, 'originAgenda.url').to_s],
      phone: [jp_first(r, 'location.phone').to_s],
      wheelchair: wheelchair(r),
      cognitive_impairment: cognitive_impairment(r),
      visual_impairment: visual_impairment(r),
      hearing_impairment: hearing_impairment(r),
      psychic_impairment: psychic_impairment(r),
      start_date: date_start,
      end_date: date_end,
      opening_hours: hour,
      image: [
          [jp_first(r, 'image.base'), jp_first(r, 'image.filename')].compact.join,
          jp(r, 'image.variants[*].filename').map{ |img| [jp_first(r, 'image.base'), img].compact.join },
        ].flatten,
    }
  end

  def wheelchair(feat)
    jp_first(feat, 'accessibility.pi') ? 'yes' : 'no'
  end

  def cognitive_impairment(feat)
    jp_first(feat, 'accessibility.ii') ? 'yes' : 'no'
  end

  def visual_impairment(feat)
    jp_first(feat, 'accessibility.vi') ? 'yes' : 'no'
  end

  def hearing_impairment(feat)
    jp_first(feat, 'accessibility.hi') ? 'yes' : 'no'
  end

  def psychic_impairment(feat)
    jp_first(feat, 'accessibility.pi') ? 'yes' : 'no'
  end

  def map_native_properties(feat, properties)
    properties.transform_values do |path|
      jp(feat, path)
    end
  end

  def each
    if ENV['NO_DATA']
      []
    else
      event = self.class.fetch_event("agendas/#{@settings.agenda_uid}/events/#{@settings.event_uid}", {
        key: @settings.key
      })

      # event.first['timings'].each do |timing|
      #   event.first['firstTiming'] = timing
      # logger.info(event)
      super(event)
      # end

    end
  end
end
