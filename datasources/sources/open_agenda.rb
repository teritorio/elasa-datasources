# frozen_string_literal: true
# typed: true

require 'date'
require 'json'
require 'http'
require 'active_support/all'


require 'jsonpath'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'
require_relative 'open_agenda_mixin'

# https://developers.openagenda.com/10-lecture/

class OpenAgendaSource < Source
  # OpenAgendaSource::Settings
  # url for reading requires an API key, agenda UID
  include OpenAgendaMixin

  class Settings < Source::SourceSettings
    const :key, String, name: 'key' # API key
    const :agenda_uid, T.nilable(String), name: 'agenda_uid' # Agenda UID
    const :website_details_url, T.nilable(String)
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

  def self.fetch(path, query, key = 'events', size = 100, max_retry: 10, sleeping_time: 0.3)
    results = T.let(Set.new, T::Set[T.untyped])
    retries = T.let(0, Integer)

    after = T.let([], T.untyped)

    query = query.merge({ after: after, size: size })
    next_url = T.let(build_url(path, query), T.nilable(String))

    total = T.let(0, Integer)
    while next_url
      response = HTTP.follow.get(next_url)
      raise [next_url, response].inspect unless response.status.success?

      json = JSON.parse(response.body)
      total = T.let(T.must(json['total']), Integer)

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
        'description' => {
          '@default' => {
            'fr-FR' => 'Description'
          }
        },
        'agenda' => {
          '@default' => {
            'fr-FR' => "Nom de l'agenda"
          },
        },
        'agenda:id' => {
          '@default' => {
            'fr-FR' => "Identifiant de l'agenda"
          },
        },
        'agenda:name' => {
          '@default' => {
            'fr-FR' => "Nom de l'agenda"
          },
        },
        'keywords' => {
          '@default' => {
            'fr-FR' => 'Mots-clés'
          }
        }
      }.merge(OpenAgendaMixin::I18N_IMPAIREMENT),
      schema: {
        'properties' => {
          'description' => {
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

  @@lang = HashExcep[{
    'fr' => 'fr-FR',
    'en' => 'en-US',
    'es' => 'es-ES',
    'it' => 'it-IT',
    'de' => 'de-DE',
    'nl' => 'nl-NL',
  }]

  def i18n_keys(trans)
    return if trans.nil?

    trans.transform_keys{ |k| @@lang[k] }
  end

  def map_tags(feat)
    r = feat
    date_start, date_end, hour = openning(r)

    {
      name: i18n_keys(jp_first(r, 'title')),
      description: i18n_keys(jp_first(r, 'longDescription')),
      addr: {
        street: jp_first(r, 'location.address'),
        postcode: jp_first(r, 'location.postalCode'),
        city: jp_first(r, 'location.city'),
        country: jp_first(r, 'country.fr') || jp_first(r, 'location.countryCode'),
      }.compact_blank,
      website: [jp_first(r, 'location.website').to_s, jp_first(r, 'originAgenda.url').to_s].compact_blank,
      'website:details': { 'fr-FR' => @settings.website_details_url&.gsub('{{id}}', r['uid'].to_s) }.compact_blank,
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
    [
      jp_first(feat, 'location.phone'),
      jp_first(feat, 'registration[?(@.type == "phone")].value'),
    ].compact_blank
  end

  def email(feat)
    [
      jp_first(feat, 'location.email'),
      jp_first(feat, 'registration[?(@.type == "email")].value'),
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
        id: @settings.agenda_uid,
        name: jp_first(feat, 'originAgenda.title'),
      },
      short_description: i18n_keys(jp_first(feat, 'description')),
      keywords: jp(feat, 'keywords.fr').flatten.compact_blank,
    })
  end

  def each(&block)
    if ENV['NO_DATA']
      loop([], &block)
    else
      events = self.class.fetch("agendas/#{@settings.agenda_uid}/events", {
        key: @settings.key,
        detailed: 1,
        longDescriptionFormat: 'HTML',
        'timings[gte]' => Time.now.utc.to_date,
      })
      loop(events, &block)
    end
  end
end
