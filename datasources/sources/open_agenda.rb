# frozen_string_literal: true
# typed: false

require 'date'
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

  def self.fetch(path, query, key = 'events', size = 100, **kwargs)
    max_retry = kwargs[:max_retry] || 10
    sleeping_time = kwargs[:sleeping_time] || 0.3
    results = T.let(Set.new, T::Set[T.untyped])
    retries = T.let(0, Integer)

    after = []

    query = query.merge({ after: after, size: size })
    next_url = T.let(build_url(path, query), T.nilable(String))

    while next_url
      response = HTTP.follow.get(next_url)
      raise [next_url, response].inspect unless response.status.success?

      json = JSON.parse(response.body)
      total = json['total']

      if json[key].empty? && retries < max_retry
        retries += 1
      else
        retries = 0
        results.merge(json[key])

        after = json['after']
        break if !after

        query.delete(:after)
        next_url = T.let(build_url(path, query.merge({ after: after })), T.nilable(String))
      end
      sleep sleeping_time
    end

    if results.size < total
      raise "Not all results fetched. Expected #{total}, got #{results.size}"
    end

    results.to_a
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
        jp_first(feat, 'location.longitude').to_f,
        jp_first(feat, 'location.latitude').to_f
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
        'agenda' => {
          '@default' => {
            'fr' => "Nom de l'agenda"
          },
        },
        'agenda:id' => {
          '@default' => {
            'fr' => "Identifiant de l'agenda"
          },
        },
        'agenda:name' => {
          '@default' => {
            'fr' => "Nom de l'agenda"
          },
        },
        'keywords' => {
          '@default' => {
            'fr' => 'Mots-clés'
          }
        }
      }.merge(OpenAgendaMixin::I18N_IMPAIREMENT),
      schema: {
        'properties' => {
          'long_description' => {
            '$ref' => '#/$defs/multilingual',
          },
          'agenda' => {
            'type' => 'object',
            'additionalProperties' => {
              'type' => 'objects',
              'properties' => {
                'id' => { 'type' => 'string' },
                'name' => { 'type' => 'string' },
              },
            },
          },
          'keywords' => {
            'type' => 'object',
            'additionalProperties' => {
              'type' => 'array',
              'items' => {
                'type' => 'string',
              },
            }
          }
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
      addr: {
        street: jp_first(r, 'location.address'),
        postcode: jp_first(r, 'location.postalCode'),
        city: jp_first(r, 'location.city'),
        country: jp_first(r, 'country.fr') || jp_first(r, 'location.countryCode'),
      },
      website: [jp_first(r, 'location.website').to_s, jp_first(r, 'originAgenda.url').to_s].compact_blank,
      phone: phone(r),
      email: email(r),
      wheelchair: wheelchair(r),
      start_date: date_start,
      end_date: date_end,
      opening_hours: hour,
      image: [
        [jp_first(r, 'image.base'), jp_first(r, 'image.filename')].compact.join,
        jp(r, 'image.variants[*].filename').map{ |img| [jp_first(r, 'image.base'), img].compact.join },
      ].flatten,
    }
  end

  def phone(feat)
    # phone_regex = /^(?:(?:(?:\+|00)33\D?(?:\D?\(0\)\D?)?)|0){1}[1-9]{1}(?:\D?\d{2}){4}$/m
    [
      jp_first(feat, 'location.phone'),
      jp_first(feat, 'registration[?(@.type == "phone")].value'),
      # jp_first(feat, 'longDescription.fr').match(phone_regex)&.to_s
    ].compact_blank
  end

  def email(feat)
    email_regex = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z]{2,}\b/i
    [
      jp_first(feat, 'location.email'),
      jp_first(feat, 'registration[?(@.type == "email")].value'),
      jp_first(feat, 'longDescription.fr')&.match(email_regex)&.to_s
  ].compact_blank
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
    properties.merge({
      cognitive_impairment: cognitive_impairment(feat),
      visual_impairment: visual_impairment(feat),
      hearing_impairment: hearing_impairment(feat),
      psychic_impairment: psychic_impairment(feat),
      agenda: {
        id: @settings.agenda_uid.to_s,
        name: jp_first(feat, 'originAgenda.title'),
      },
      long_description: jp_first(feat, 'longDescription'),
      keywords: jp(feat, 'keywords'),
    })
  end

  def each
    if ENV['NO_DATA']
      []
    else
      event = self.class.fetch_event("agendas/#{@settings.agenda_uid}/events/#{@settings.event_uid}", {
        key: @settings.key
      })
      super(event)
    end
  end
end
