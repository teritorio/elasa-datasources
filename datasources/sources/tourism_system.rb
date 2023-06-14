# frozen_string_literal: true
# typed: false

require 'jsonpath'
require 'open-uri'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


def jp(object, path)
  JsonPath.on(object, "$.#{path}")
end

class TourismSystemSource < Source
  def initialize(source_id, attribution, settings, path)
    super(source_id, attribution, settings, path)
    @basic_auth = settings[:basic_auth]
    @id = settings[:id]
    @playlist_id = settings[:playlist_id]
    @thesaurus = settings[:thesaurus]
    @website_details_url = settings[:website_details_url]
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

    data = []
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

  def stars(code)
    {
      # Hotels
      '06.04.01.03.01' => '1',
      '06.04.01.03.02' => '2',
      '06.04.01.03.03' => '3',
      '06.04.01.03.04' => '4',
      '06.04.01.03.05' => '4S',
      '99.06.04.01.03.01' => '5',
    }[code]
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
    hours = day['schedules'].select{ |s| s['startTime'] }.collect{ |s|
      hours_start = s['startTime'][0..4]
      hours_end = s['endTime'].nil? ? nil : s['endTime'][0..4]
      hours_start + (hours_end.nil? ? '+' : "-#{hours_end}")
    }.join(',')
    [d, hours]
  end

  def self.openning(periods)
    min_date_on = nil
    max_date_off = nil

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

      day_hour = (((day_by_types['09.03.02'] || []) + (day_by_types['09.03.04'] || [])).pluck('days').flatten(1).collect{ |day|
        # Ouverture, Visite
        openning_day(day)
      } + ((day_by_types['09.03.01'] || []) + (day_by_types['09.03.03'] || [])).pluck('days').flatten(1).collect{ |day|
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
    events&.pluck('criterion')&.select{ |c|
      # Fêtes et Manifestations - Types
      c.start_with?('02.01.03.04')
    }&.collect{ |c|
      t = @@event_type[c]
      if t.nil?
        puts raise("Missing #{tm['libelleFr']}")
      else
        t
      end
    }&.compact
  end

  def each
    raw = self.class.fetch_data(@basic_auth, "/content/ts/#{@id}/#{@playlist_id}")
    puts "#{self.class.name}: #{raw.size}"

    raw.each{ |f|
      id = f.dig('data', 'dublinCore', 'externalReference')
      website_details = @website_details_url.gsub('#{id}', id)
      event = f.dig('data', 'dublinCore', 'classifications')&.pluck('classification')&.include?('02.01.03') # Fêtes et Manifestations
      date_on, date_off, osm_openning_hours = !f.dig('data', 'periods').nil? && self.class.openning(f['data']['periods'])
      yield ({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [
            jp(f, '.geolocations..longitude').first.to_f,
            jp(f, '.geolocations..latitude').first.to_f,
          ],
        },
        properties: {
          id: id,
          updated_at: f.dig('data', 'dublinCore', 'modified'),
          source: @attribution,
          tags: {
            name: f.dig('metadata', 'name'),
            description: f.dig('data', 'dublinCore', 'description'),
            phone: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.01")]')&.pluck('particular')&.compact_blank,
            email: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.04")]')&.pluck('particular')&.compact_blank,
            website: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.05")]')&.pluck('particular')&.compact_blank,
            'website:details': website_details,
            facebook: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="99.04.02.01")]')&.pluck('particular')&.compact_blank,
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
            cuisine: (
              f.dig('data', 'dublinCore', 'criteria')&.pluck('criterion')&.select{ |v|
                v.start_with?('02.01.13.03.') || v.include?('.00.02.01.13.03.')
              }&.map{ |v|
                @thesaurus[v] || v
              }),
            opening_hours: osm_openning_hours,
            start_date: event && date_on,
            end_date: event && date_off,
            stars: stars(jp(f, '.ratings.officials..ratingLevel').select{ |s| s.include?('06.04.01.03.') }.first),
            event: self.class.events(f.dig('data', 'dublinCore', 'criteria')),
          }.compact_blank,
        }.compact_blank,
      })
    }
  end
end
