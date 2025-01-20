# frozen_string_literal: true
# typed: true

require 'jsonpath'
require 'open-uri'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


class TourismSystemSource < Source
  extend T::Sig

  class Settings < Source::SourceSettings
    const :basic_auth, String
    const :id, String
    const :playlist_id, String
    const :thesaurus, T::Hash[String, String]
    const :website_details_url, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def jp(object, path)
    JsonPath.on(object, "$.#{path}")
  end

  def self.fetch(basic_auth, path)
    url = "https://#{basic_auth}@api.tourism-system.com#{path}"
    uri = URI.parse(url)

    uri_options = {}
    if !uri.userinfo.nil?
      uri_options[:http_basic_authentication] = [CGI.unescape(uri.user), CGI.unescape(uri.password)]
      uri.user = nil
      uri.password = nil
    end
    file = OpenURI.open_uri(uri, uri_options)

    JSON.parse(file.read)
  end

  def self.fetch_data(basic_auth, path)
    results = T.let([], T::Array[T.untyped])
    start = 0
    size = 1000

    data = T.let([], T::Array[T.untyped])
    # Deals with stange remote paging API
    while start == 0 || data.size >= size - 1
      next_path = path + "?start=#{start}&size=#{size}"
      data = fetch(basic_auth, next_path)['data']
      results += data
      start += size
    end
    results
  end

  def https(url)
    url.gsub(%r{^http://}, 'https://')
  end

  @@awards = {
    tournesol: %w[tournesol tournesols],
    soleil: %w[soleil soleils],
    epi: %(épi épis),
    cle: %(clé clés),
    toque: %(toque toques),
    fleurs: %(fleur fleurs),
    cheminee: %(cheminée cheminées),
    lutin_bleu: ['Lutin bleu (simple)', 'Lutins bleus (variés)'],
    lutin_blanc: ['Lutin blanc (simple)', 'Lutins blancs (variés)'],
    lutin_rouge: ['Lutin rouge (simple et complets)', 'Lutins rouges (trés bon et complets)'],
  }

  def ratings(ratings)
    ((jp(ratings, '.officials..ratingLevel') || []) + (jp(ratings, '.labels..ratingLevel') || [])).collect{ |level|
      @settings.thesaurus[level]&.split(' ', 2)
    }.collect{ |level, award|
      if level.to_i.to_s == level && level != '0'
        if award.start_with?('étoile')
          ['stars', award == 'étoiles Luxe' ? '4S' : level]
        else
          symb_award = @@awards.find{ |_symb, matches| matches.include?(award) }
          if symb_award.nil?
            raise [level, award].inspect
          end

          ["award:#{symb_award[0]}", level]
        end
      end
    }.compact.uniq.to_h
  end

  @@month = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]

  def self.date(date)
    month = @@month[date[5..6].to_i - 1]
    day = date[8..9]
    [month, day].join(' ')
  end

  @@days = {
    '09.02.01' => 'Su', # Dimanche
    '09.02.02' => 'Mo', # Lundi
    '09.02.03' => 'Tu', # Mardi
    '09.02.04' => 'We', # Mercredi
    '09.02.05' => 'Th', # Jeudi
    '09.02.06' => 'Fr', # Vendredi
    '09.02.07' => 'Sa', # Samedi
    '09.02.08' => nil, # Tous les jours
  }

  def self.openning_day(day)
    d = @@days[day['day']]
    hours = day['schedules']&.select{ |s| s['startTime'] }&.collect{ |s|
      hours_start = s['startTime'][0..4]
      hours_end = s['endTime'].nil? ? nil : s['endTime'][0..4]
      hours_start + (hours_end.nil? ? '+' : "-#{hours_end}")
    }&.join(',')
    [d, hours]
  end

  def self.openning(periods)
    min_date_on = T.let(nil, T.nilable(String))
    max_date_off = T.let(nil, T.nilable(String))

    osm_openning_hours = periods.select{ |p|
      if ['09.01.01', '09.01.05', '09.01.06', '09.01.07', nil].exclude?(p['type'])
        raise p['type'].inspect
      end

      ['09.01.01', '09.01.05', '09.01.06', '09.01.07'].include?(p['type']) # Accueil, Manifestation, Ouverture, Réservation
    }.collect{ |p|
      min_date_on = [min_date_on, p['startDate'][0..9]].compact.min
      max_date_off = [max_date_off, p['endDate'][0..9]].compact.max

      start_date = date(p['startDate'])
      end_date = date(p['endDate'])
      end_date = nil if start_date == end_date
      date = [start_date, end_date].compact.join('-')

      day_by_types = (p['days'] || []).group_by{ |day|
        day['type']
      }

      day_hour = (((day_by_types['09.03.02'] || []) + (day_by_types['09.03.04'] || [])).pluck('days').flatten(1).compact.collect{ |day|
        # Ouverture, Visite
        openning_day(day)
      } + ((day_by_types['09.03.01'] || []) + (day_by_types['09.03.03'] || [])).pluck('days').flatten(1).compact.collect{ |day|
        # Fermeture, Relache
        openning_day(day) + ['off']
      }).group_by{ |od|
        od[1..]
      }.collect{ |key, vs|
        days = vs.collect(&:first).join(',')
        ([days.empty? ? nil : days] + key).compact.join(' ')
      }

      ([date] + day_hour).compact.join(' ')
    }.join(';')

    [min_date_on, max_date_off, osm_openning_hours == '' ? nil : osm_openning_hours]
  end

  # https://www.datatourisme.fr/ontology/core/#EntertainmentAndEvent
  @@event_type = {
    # SaleEvent
    '02.01.03.04.04' => 'SaleEvent', # Manifestation commerciale, Generic
    # '' => 'BricABrac',
    # '' => 'FairOrShow',
    # '' => 'Market',
    # '' => 'OpenDay',
    # '' => 'GarageSale',
    # BusinessEvent
    # '' => 'TrainingWorkshop',
    # '' => 'ExecutiveBoardMeeting',
    # '' => 'Congress',
    # '' => 'BoardMeeting',
    # '' => 'WorkMeeting',
    # '' => 'Seminar',
    # SocialEvent
    # '' => 'SocialEvent', # Generic
    # '' => 'LocalAnimation',
    # '' => 'Carnival',
    # '' => 'Parade',
    '02.01.03.04.10' => 'TraditionalCelebration', # Traditions et folklore
    # '' => 'PilgrimageAndProcession',
    '02.01.03.04.07' => 'ReligiousEvent', # Religieuse
    # CulturalEvent
    '02.01.03.04.01' => 'CulturalEvent', # Culturelle, Generic
    '02.01.03.04.05' => 'Concert', # Musique
    # '' => 'Conference',
    # '' => 'ArtistSigning',
    # '' => 'ChildrensEvent',
    # '' => 'Exhibition',
    # '' => 'Festival',
    # '' => 'Reading',
    # '' => 'Opera',
    # '' => 'TheaterEvent',
    # '' => 'ScreeningEvent',
    # '' => 'Recital',
    '02.01.03.04.08' => 'VisualArtsEvent', # Son et Lumière
    # '' => 'ShowEvent',
    # '' => 'CircusEvent',
    '02.01.03.04.02' => 'DanceEvent', # Danse
    # '' => 'Harvest',
    # SportsEvent
    '02.01.03.04.09' => 'SportsEvent', # Sports et loisirs, Generic
    # '' => 'SportsCompetition',
    # '' => 'SportsDemonstration',
    # '' => 'Game',
    # '' => 'Rally',
    # '' => 'Rambling',

    # Other. Not part of datatourisme ontology
    '02.01.03.04.03' => 'Other', # Insolite
    '02.01.03.04.06' => 'Other', # Nature et détente
  }

  def self.events(events)
    events = events.values if events.is_a?(Hash) # Should be an array, but buggy remote API may return an Hash

    events&.pluck('criterion')&.select{ |c|
      # Fêtes et Manifestations - Types
      c.start_with?('02.01.03.04')
    }&.collect{ |c|
      t = @@event_type[c]
      raise "Missing #{c}" if t.nil?

      t
    }&.compact
  end

  @@capacities = HashExcep[{
    '14.01.01' => nil, # Appartements # No OSM tags for that
    '14.01.02' => 'rooms', # Chambres
    '14.01.03' => nil, # Hébergements # No OSM tags for that
    '14.01.04' => 'pitches', # Emplacements
    '14.01.05' => 'tents', # Tentes
    '14.01.06' => 'rooms', # Salles # FIXME Not sure about this mapping
    '14.01.07' => 'persons', # Personnes
    '99.14.01.07' => 'persons', # Groupes (Capacité max.)"
    # Other OSM avaiables tags
    # caravans
    # beds
  }]

  def self.capacities(global_capacities)
    (global_capacities || {}).collect{ |global_capacity|
      [global_capacity['type'], global_capacity['capacity']]
    }.select{ |type, capacity|
      if !type.start_with?('14.01.') && !type.start_with?('99.14.01.')
        false
      else
        !@@capacities[type].nil? && !capacity.nil? && capacity.to_i != 0
      end
    }.to_h{ |type, capacity|
      ["capacity:#{@@capacities[type]}", capacity.to_i]
    }
  end


  # @@tags = {
  #   # Patrimoine naturel
  #   '193.02.01.12.01.01' => { 'boundary' => 'protected_area', 'leisure' => 'nature_reserve' }, # Découverte faune et flore
  #   '193.02.01.12.01.02' => { 'water' => 'lake' }, # Lacs
  #   '193.02.01.12.01.04' => { 'boundary' => 'protected_area', 'protect_class' => '4' }, # Parcs Naturels Régionaux
  #   '193.02.01.12.01.05' => { 'tourism' => 'viewpoint' }, # Point de vue / Panorama
  #   '317.02.01.12.01.01' => { 'tourism' => 'viewpoint' }, # Panoramas
  #   '317.02.01.12.01.03' => { 'natural' => 'mountain_range' }, # Massifs et montagnes
  #   '317.02.01.12.01.04' => { 'natural' => 'bay' }, # Baie
  # }

  # def main_tags(classifications)
  #   classifications&.collect{ |classification|
  #     @@tags[classification]
  #   }&.compact&.inject(:merge) || {}
  # end

  def each(&block)
    loop(ENV['NO_DATA'] ? [] : self.class.fetch_data(@settings.basic_auth, "/content/ts/#{@settings.id}/#{@settings.playlist_id}"), &block)
  end

  def map_id(feat)
    feat.dig('data', 'dublinCore', 'externalReference')
  end

  def map_updated_at(feat)
    feat.dig('data', 'dublinCore', 'modified')
  end

  def map_geometry(feat)
    return if jp(feat, '.geolocations')&.first.blank?

    {
      type: 'Point',
      coordinates: [
        jp(feat, '.geolocations..longitude').first.to_f,
        jp(feat, '.geolocations..latitude').first.to_f
      ]
    }
  end

  def map_tags(feat)
    f = feat
    website_details = @settings.website_details_url.gsub('{{id}}', map_id(feat))
    event = f.dig('data', 'dublinCore', 'classifications')&.pluck('classification')&.include?('02.01.03') # Fêtes et Manifestations
    date_on, date_off, osm_openning_hours = !f.dig('data', 'periods').nil? && self.class.openning(f['data']['periods'])
    {
      name: f['data']['businessNames'],
      description: f.dig('data', 'dublinCore', 'description'),
      phone: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.01")]')&.pluck('particular')&.compact_blank,
      email: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.04")]')&.pluck('particular')&.compact_blank,
      website: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.05")]')&.pluck('particular')&.compact_blank,
      'website:details': { 'fr-FR' => website_details }.compact_blank,
      facebook: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="99.04.02.01")]')&.pluck('particular')&.first,
      image: jp(f, '.multimedia[*][?(@.type=="03.01.01")].URL').map{ |u| https(u) }, # 03.01.01 = Image
      addr: {
          street: [ # 04.03.13 = Etab/Lieu/Structure
          jp(f, '.contacts[*][?(@.type=="04.03.13")]..address1'),
          jp(f, '.contacts[*][?(@.type=="04.03.13")]..address2'),
          jp(f, '.contacts[*][?(@.type=="04.03.13")]..address3'),
        ].compact_blank.join(', '),
          postcode: jp(f, '.contacts[*][?(@.type=="04.03.13")]..zipCode').first,
          city: [
          jp(f, '.contacts[*][?(@.type=="04.03.13")]..commune'),
          # jp(f, '.contacts[*][?(@.type=="04.03.13")]..bureauDistrib'), # FIXME, not sure about property name
          # jp(f, '.contacts[*][?(@.type=="04.03.13")]..cedex'), # FIXME, not sure about property name
        ].compact_blank.join(', '),
          country: [
          # jp(f, '.contacts[*][?(@.type=="04.03.13")]..state'), # FIXME, not sure about property name
          jp(f, '.contacts[*][?(@.type=="04.03.13")]..country'),
        ].compact_blank.join(', '),
      }.compact_blank,
      # cuisine: (
      #   f.dig('data', 'dublinCore', 'criteria')&.pluck('criterion')&.select{ |v|
      #     v.start_with?('02.01.13.03.') || v.include?('.00.02.01.13.03.')
      #   }&.map{ |v|
      #     @settings.thesaurus[v] || v
      #   }),
      opening_hours: osm_openning_hours,
      start_date: event && date_on,
      end_date: event && date_off,
      event: self.class.events(f.dig('data', 'dublinCore', 'criteria')),
    }.merge(
      # main_tags(f.dig('data', 'dublinCore', 'criteria')&.pluck('criterion')),
      self.class.capacities(jp(f, '.capacities[*].globalCapacities',).flatten(1)),
      ratings(jp(f, '.ratings')),
    )
  end

  def map_native_properties(feat, _properties)
    criterion = jp(feat, '$.data.dublinCore.criteria..criterion')

    criterion.collect{ |t|
      std = t[0] == '0' ? t : t.split('.', 2)[1]
      [std.split('.')[0..3], @settings.thesaurus[t]]
    }.group_by(&:first).transform_values{ |values| values.collect(&:last) }.transform_keys{ |key|
      nature = @settings.thesaurus[key[0..2].join('.')]
      segmentation = @settings.thesaurus[key.join('.')]
      "#{nature}-#{segmentation}".parameterize
    }
  end
end
