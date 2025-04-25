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

  def valid_url(id, tag, url)
    return if url.blank?

    valid = url =~ URI::DEFAULT_PARSER.make_regexp && url.start_with?('https://') && url.split('/')[2].include?('.') && !url.split('/')[2].include?(' ')
    if !valid
      logger.info("Invalid URL for #{id}: #{tag}=#{url}")
    end
    valid ? url : nil
  end

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

  def self.openning(ouvertures, openning_days)
    date_ons = []
    date_offs = []
    hours = ouvertures.split('#').collect{ |ouverture|
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

      dates = TourinsoftSirtaquiMixin::FORMAT_MONTH_RANGE.call(date_on, date_off)

      days_hours = method(openning_days).call(parts[2..]&.collect(&:presence) || []).presence
      [dates, days_hours&.join(',')].compact.join(' ')
    }.compact_blank.join(';').presence
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

  def extract_steps_from_feature(feature)
    feature['ETAPE']&.split('#')&.collect{ |step|
      %w[SyndicObjectID name description _ _ LON LAT image image_description image_source].zip(
        step.split('|').collect(&:presence)
      ).to_h
    }&.select{ |step| !step['LON'].nil? && !step['LAT'].nil? }&.each_with_index&.collect{ |step, index|
      step['SyndicObjectID'] = "#{map_id([nil, feature])}.#{@destination_id}.#{index}"
      step['name'] = [step['id'], step['name']].compact.join(' - ') if !step['id'].nil? && !step['name'].nil?
      step['LON'] = step['LON']&.to_f
      step['LAT'] = step['LAT']&.to_f
      step['Updated'] = feature['Updated']
      step['waypoint:type'] = 'waypoint'
      step.compact
    } || []
  end

  sig { returns(SchemaRow) }
  def schema
    super.with(
      i18n: {
        'route' => {
          'values' => TourinsoftSirtaquiMixin::PRACTICES.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr-FR' => v } } }
        }
      }.merge(
        *TourinsoftSirtaquiMixin::PRACTICES.values.collect { |practice|
          {
            "route:#{practice}:difficulty" => {
              'values' => TourinsoftSirtaquiMixin::DIFFICULTIES.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr-FR' => v } } }
            }
          }
        }
      )
    )
  end

  def select(feat)
    super && (feat.first != :feature ||
      !feat.last['PHOTO'].nil? &&
      (
        feat.last['ObjectTypeName'] != 'Fêtes et manifestations' || (
          feat.last['DATESCOMPLET'].present? && feat.last['DATES'].present?
        )
      ))
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        (feat.last['LON'].presence || feat.last['GmapLongitude']).to_f,
        (feat.last['LAT'].presence || feat.last['GmapLatitude']).to_f
      ]
    }
  end

  def pdfs(feat)
    {
      'en-US' => feat['DOCPDFGB'].nil? ? nil : "#{@settings.photo_base_url}#{feat['DOCPDFGB']}",
      'fr-FR' => feat['DOCPDFFR'].nil? ? nil : "#{@settings.photo_base_url}#{feat['DOCPDFFR']}",
      'es-ES' => feat['DOCPDFES'].nil? ? nil : "#{@settings.photo_base_url}#{feat['DOCPDFES']}",
    }.compact_blank
  end

  def ouverture(feat)
    if feat['OUVERTURECOMPLET']
      self.class.openning(
        feat['OUVERTURECOMPLET'],
        :openning_seven_days
      )
    elsif feat['OUVERTURE'] || feat['DATESCOMPLET']
      self.class.openning(
        feat['OUVERTURE'] || feat['DATESCOMPLET'],
        :openning_one_days
      )
    end
  end

  def features
    @features_cache ||= self.class.fetch(@settings.client, @settings.syndication).collect{ |feat| [:feature, feat] }
    @features_cache
  end

  sig { returns(T::Array[MetadataRow]) }
  def metadatas
    has_steps = features.first&.last&.key?('ETAPE')
    super + (has_steps ? [
      MetadataRow.new({
        data: {
          "#{@destination_id}-steps" => Metadata.from_hash({
            'name' => { 'en-US' => "#{@destination_id}-steps" },
            'attribution' => @settings.attribution,
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

  def each(&block)
    if ENV['NO_DATA']
      loop([], &block)
    else
      features_steps = features.collect { |feature|
        feature_steps = extract_steps_from_feature(feature.last)
        feature.last['step_ids'] = feature_steps.pluck('SyndicObjectID')
        [feature] + feature_steps.collect{ |feat| [:step, feat] }
      }.flatten(1)
      loop(features_steps, &block)
    end
  end

  def map_tags(type_feat)
    r = super
    return r if !r.nil?

    type, feat = type_feat
    type == :step ? map_step_tags(feat) : nil
  end

  def map_step_tags(feat)
    r = feat
    id = map_id([nil, r])
    {
      ref: {
        'FR:CRTA.step': id,
      },
      name: { 'fr-FR' => r['name'] }.compact_blank,
      description: { 'fr-FR' => r['description'] }.compact_blank,
      image: [r['image']].compact,
      # image_description
      # image_source
      route: {
        'waypoint:type': r['waypoint:type'],
      },
    }
  end

  def map_feature_tags(feat)
    r = feat

    date_on, date_off, osm_openning_hours = ouverture(r)

    id = map_id([nil, r])
    {
      ref: {
        'FR:CRTA': id,
      },
      name: { 'fr-FR' => r['NOMOFFRE'] }.compact_blank,
      description: { 'fr-FR' => r['DESCRIPTIF'] }.compact_blank,
      website: multiple_split(r, %w[URL URLCOMPLET], 0),
      'website:details': { 'fr-FR' => @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID']) }.compact_blank,
      phone: multiple_split(r, %w[TEL TELCOMPLET TELMOB TELMOBCOMPLET], 0),
      email: multiple_split(r, %w[MAIL MAILCOMPLET], 0),
      facebook: valid_url(id, :facebook, r['FACEBOOK']),
      twitter: valid_url(id, :twitter, r['TWITTER']),
      instagram: valid_url(id, :instagram, r['INSTAGRAM']),
      linkedin: valid_url(id, :linkedin, r['LINKEDIN']),
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
        event: multiple_split(r, ['CATFMA']).collect{ |t| TourinsoftSirtaquiMixin::EVENT_TYPE[t] }.uniq,
      } || {},
      r['TYPE'] == 'Restaurant' ? cuisines(multiple_split(r, ['SPECIALITES'])) : {},
      r['TYPE']&.include?('Hôtel') ? { tourism: 'hotel' } : {},
    )
  end

  def map_refs(type_feat)
    type, feat = type_feat
    type == :feature ? feat['step_ids'] : nil
  end
end
