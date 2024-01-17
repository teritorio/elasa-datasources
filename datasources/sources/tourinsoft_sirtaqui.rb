# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft'
require_relative 'tourinsoft_sirtaqui_mixin'


class TourinsoftSirtaquiSource < TourinsoftSource
  extend T::Sig
  include TourinsoftSirtaquiMixin

  class Settings < TourinsoftSource::Settings
    const :photo_base_url, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  @@days = HashExcep[{
    'Lundi' => 'Mo',
    'Lundi matin' => 'Mo',
    'Lundi midi' => 'Mo',
    'Lundi après midi' => 'Mo',
    'Lundi soir' => 'Mo',
    'Mardi' => 'Tu',
    'Mardi matin' => 'Tu',
    'Mardi midi' => 'Tu',
    'Mardi après midi' => 'Tu',
    'Mardi soir' => 'Tu',
    'Mercredi' => 'We',
    'Mercredi matin' => 'We',
    'Mercredi midi' => 'We',
    'Mercredi après midi' => 'We',
    'Mercredi soir' => 'We',
    'Jeudi' => 'Th',
    'Jeudi matin' => 'Th',
    'Jeudi midi' => 'Th',
    'Jeudi après midi' => 'Th',
    'Jeudi soir' => 'Th',
    'Vendredi' => 'Fr',
    'Vendredi matin' => 'Fr',
    'Vendredi midi' => 'Fr',
    'Vendredi après midi' => 'Fr',
    'Vendredi soir' => 'Fr',
    'Samedi' => 'Sa',
    'Samedi matin' => 'Sa',
    'Samedi midi' => 'Sa',
    'Samedi après midi' => 'Sa',
    'Samedi soir' => 'Sa',
    'Dimanche' => 'Su',
    'Dimanche matin' => 'Su',
    'Dimanche midi' => 'Su',
    'Dimanche après midi' => 'Su',
    'Dimanche soir' => 'Su',
  }]

  @@month = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]

  def self.format_days_hours(open_days, open1, close1, open2, close2)
    hours = [
      if open1.nil?
        nil
      else
        (open1 + (close1.nil? ? '+' : "-#{close1}"))
      end,
      if open2.nil?
        nil
      else
        (open2 + (close2.nil? ? '+' : "-#{close2}"))
      end,
    ].compact.join(',').presence
    [[open_days, hours].compact.join(' ')].compact_blank if hours
  end

  def self.openning_one_days(parts)
    open1, close1, open2, close2, close_days = parts

    close_days = close_days&.split(/(?:-| (?=[A-Z]))/)&.collect{ |d| @@days[d] }
    open_days = close_days.nil? ? nil : (%w[Mo Tu We Th Fr Sa Su] - close_days).join(',')

    format_days_hours(open_days, open1, close1, open2, close2)
  end

  def self.openning_seven_days(parts)
    _close_days = parts.pop
    parts.each_slice(4).with_index.group_by{ |open_close, _day_index| open_close }.collect{ |open_close, f|
      days = f.collect{ |ff| %w[Mo Tu We Th Fr Sa Su][ff[1]] }.join(',')
      open1, close1, open2, close2 = open_close
      format_days_hours(days, open1, close1, open2, close2)
    }.compact_blank
  end

  def self.format_month_range(date_on, date_off)
    on = [@@month[date_on.split('-')[1].to_i - 1], date_on.split('-')[2]].compact.join(' ') if !date_on.nil?
    off = [@@month[date_off.split('-')[1].to_i - 1], date_off.split('-')[2]].compact.join(' ') if !date_off.nil? && date_on != date_off
    [on, off].compact.join('-')
  end

  def self.openning(ouvertures, openning_days)
    date_ons = []
    date_offs = []
    opennings = ouvertures.split('#').collect{ |ouverture|
      parts = ouverture.split('|')
      date_on, date_off = parts[0..1].collect(&:presence)
      date_on, date_off = (
        if date_on && date_on[0..5] == '01/01' && date_off && date_off[0..5] == '31/12'
          [nil, nil]
        else
          [date_on, date_off].collect{ |d| d && d.split('/').reverse.join('-') }
        end
      )
      date_ons << date_on
      date_offs << date_off

      dates = format_month_range(date_on, date_off)

      days_hours = method(openning_days).call(parts[2..]&.collect(&:presence) || [])
      days_hours&.collect{ |days_hour|
        [dates, days_hour].compact.join(' ')
      }
    }.flatten(1)
    hours = opennings.join(';').presence
    if hours.nil?
      hours = format_month_range(date_ons.compact.min, date_offs.compact.max)
    end
    [date_ons.compact.min, date_offs.compact.max, hours]
  end

  def route(itis, distance)
    distance &&= distance.gsub(',', '.').to_f

    # "ITITEMPSDIF": "à pied|2h|Facile",
    itis&.split('#')&.collect{ |iti|
      practice, duration, difficulty = iti.split('|')

      practice_slug = TourinsoftSirtaquiMixin::PRACTICES[practice]

      duration = route_duration(duration)

      {
        "#{practice_slug}": {
          difficulty: TourinsoftSirtaquiMixin::DIFFICULTIES[difficulty],
          duration: duration,
          length: distance,
        }.compact_blank
      }.compact_blank
    }
  end

  sig { returns(SchemaRow) }
  def schema
    super.with(
      i18n: {
        'route' => {
          'values' => TourinsoftSirtaquiMixin::PRACTICES.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr' => v } } }
        }
      }.merge(
        *TourinsoftSirtaquiMixin::PRACTICES.values.collect { |practice|
          {
            "route:#{practice}:difficulty" => {
              'values' => TourinsoftSirtaquiMixin::DIFFICULTIES.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr' => v } } }
            }
          }
        }
      )
    )
  end

  def select(feat)
    super(feat) &&
      !feat['PHOTO'].nil? &&
      (
        feat['ObjectTypeName'] != 'Fêtes et manifestations' || (
          feat['DATESCOMPLET'].present? && feat['DATES'].present?
        )
      )
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat['LON'].to_f,
        feat['LAT'].to_f
      ]
    }
  end

  def pdfs(feat)
    feat.select{ |k, v|
      k.start_with?('DOCPDF') && !v.nil?
    }.to_h{ |k, v|
      c = k[-2..].downcase
      [c == 'gb' ? 'en' : c, "#{@settings.photo_base_url}#{v}"]
    }
  end

  def map_tags(feat)
    r = feat

    if r['OUVERTURECOMPLET']
      date_on, date_off, osm_openning_hours = self.class.openning(
        r['OUVERTURECOMPLET'],
        :openning_seven_days
      )
    elsif r['OUVERTURE'] || r['DATESCOMPLET']
      date_on, date_off, osm_openning_hours = self.class.openning(
        r['OUVERTURE'] || r['DATESCOMPLET'],
        :openning_one_days
      )
    end

    {
      ref: {
        'FR:CRTA': map_id(r),
      },
      name: { fr: r['NOMOFFRE'] }.compact_blank,
      description: { fr: r['DESCRIPTIF'] }.compact_blank,
      website: multiple_split(r, %w[URL URLCOMPLET], 0),
      'website:details': { fr: @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID']) }.compact_blank,
      phone: multiple_split(r, %w[TEL TELCOMPLET TELMOB TELMOBCOMPLET], 0),
      email: multiple_split(r, %w[MAIL MAILCOMPLET], 0),
      facebook: r['FACEBOOK'],
      twitter: r['TWITTER'],
      instagram: r['INSTAGRAM'],
      image: multiple_split(r, %w[PHOTO PHOTOCOMPLET PROPPRESENTATIONPHOTO PHOTO_DIAPO], 0)&.collect{ |p| "#{@settings.photo_base_url}#{p}" },
      addr: r['COMMUNE'] && {
        street: [r['AD1'], r['AD1SUITE'], r['AD2'], r['AD3']].compact_blank.join(', '),
        postcode: r['CP'],
        city: r['COMMUNE'],
      }.compact_blank || nil,
      route: route(r['ITITEMPSDIF'], r['DISTANCE'])&.inject({
        gpx_trace: r['DOCGPX'] && "#{@settings.photo_base_url}#{r['DOCGPX']}",
        pdf: pdfs(r),
      }, :merge)&.compact_blank,
      'capacity:beds': r['NBRELITS']&.to_i,
      'capacity:rooms': r['NBRECHAMB']&.to_i,
      'capacity:persons': r['CAPA']&.to_i,
      'capacity:caravans': r['NBRECARAVANES']&.to_i,
      'capacity:cabins': r['NBREMHOME']&.to_i,
      'capacity:pitches': r['NBREEMP']&.to_i,
      opening_hours: osm_openning_hours,
      stars: TourinsoftSirtaquiMixin::CLASS[r['CLAS']],
    }.merge(
      r['ObjectTypeName'] == 'Fêtes et manifestations' && {
        start_date: date_on,
        end_date: date_off,
        event: multiple_split(r, ['CATFMA']).collect{ |t| TourinsoftSirtaquiMixin::EVENT_TYPE[t] },
      } || {},
      r['TYPE'] == 'Restaurant' ? cuisines(multiple_split(r, ['SPECIALITES'])) : {},
      r['TYPE']&.include?('Hôtel') ? { tourism: 'hotel' } : {},
    )
  end
end
