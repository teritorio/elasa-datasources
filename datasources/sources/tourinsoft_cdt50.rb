# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft'


class TourinsoftCdt50Source < TourinsoftSource
  extend T::Generic
  SettingsType = type_member{ { upper: TourinsoftSource::Settings } } # Generic param

  @@cuisines = HashExcep[{
    'Bistrot / bar à vin' => { amenity: 'restaurant', cuisine: ['bistro'] },
    'Bistrot gastronomique' => { amenity: 'restaurant', cuisine: ['bistronomique'] },
    'Brasserie' => { amenity: 'restaurant', cuisine: ['brasserie'] },
    'Brunch' => { amenity: 'restaurant', cuisine: ['brunch'] },
    'Cuisine gastronomique' => { amenity: 'restaurant', cuisine: ['gastronomique'] },
    'Café' => { amenity: 'cafe' },
    'Cafétéria' => { amenity: 'fast_food', fast_food: 'cafeteria' },
    'Crêperie' => { amenity: 'restaurant', cuisine: ['crepe'] },
    'Cuisine inventive' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Cuisine traditionnelle' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Cuisine traditionnelle française' => { amenity: 'restaurant', cuisine: ['french'] },
    'Cuisine du monde' => { amenity: 'restaurant', cuisine: ['international'] },
    'Grill' => { amenity: 'restaurant', cuisine: ['grill'] },
    'Pizzeria' => { amenity: 'restaurant', cuisine: ['pizza'] },
    'Restauration à thème' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Restauration Rapide' => { amenity: 'fast_food' },
    'Rôtisserie' => { amenity: 'restaurant', cuisine: ['rotisserie'] },
    'Routier' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Saladerie' => { amenity: 'fast_food', cuisine: ['salad'] },
    'Salon de thé' => { amenity: 'cafe', cuisine: ['tea'] },
    'Food-Truck' => { amenity: 'fast_food' }, # FIXME: street_vendor=yes
  }]

  def self.cuisines(cuisines)
    cuisines.collect{ |cuisine|
      @@cuisines[cuisine]
    }.compact.inject(:deep_merge_array) || {}
  end

  @@practices = HashExcep[{
    'Pédestre' => 'hiking',
    'Equestre' => 'horse',
    'Vélo' => 'bicycle',
    'VTT' => 'mtb',
  }]

  @@difficulties = HashExcep[{
    nil => nil,
    'Facile' => 'easy',
    'Moyen' => 'normal',
    'Difficile' => 'hard',
  }]

  def dates_to_oh(dates)
    dates.collect{ |date|
      _year, month, day = date.split('-')
      "#{TourinsoftSirtaquiMixin::MONTH[month.to_i - 1]} #{day}"
    }
  end

  def parse_dates(dates)
    dates = dates.split('<br />').collect{ |d| d.split('/').reverse.join('-') }
    [dates.min, dates.max, dates_to_oh(dates)]
  end

  def route(feat)
    types = multiple_split(feat, ['Type'])
    length = feat['LongueurKM']&.to_f || 0
    durations_difficulty = multiple_split(feat, ['PratiqueDureeDifficulte'], 0..-1).to_h{ |practice, durations, difficulty|
      [practice, [durations, difficulty]]
    }

    types.collect{ |type|
      duration, difficulty = durations_difficulty[type]
      if duration.present?
        d = duration.split(':', 2).collect(&:to_i)
        duration = d[0] * 60 + d[1]
      end
      {
        "#{@@practices[type]}": {
          duration: duration,
          length: if length == 0
                    duration.nil? ? 0 : nil
                  else
                    length
                  end, # Ensure at least duration or length are present
          difficulty: @@difficulties[difficulty]
        }.compact_blank
      }
    }
  end

  # https://www.datatourisme.fr/ontology/core/#EntertainmentAndEvent
  @@event_type = {
    # SaleEvent
    'Manifestation commerciale' => 'SaleEvent', # Generic
    'Brocantes et vide-greniers' => %w[BricABrac GarageSale],
    'Salons, foires et marchés' => %w[FairOrShow Market],
    # '' => 'OpenDay',
    # BusinessEvent
    'Initiations - Ateliers - Stages' => 'TrainingWorkshop',
    # '' => 'ExecutiveBoardMeeting',
    # '' => 'Congress',
    # '' => 'BoardMeeting',
    # '' => 'WorkMeeting',
    # '' => 'Seminar',
    # SocialEvent
    # '' => 'SocialEvent', # Generic
    'Fêtes locales et du terroir' => 'LocalAnimation',
    'Fêtes - Animations de fin d\'année' => 'LocalAnimation',
    # '' => 'Carnival',
    # '' => 'Parade',
    'Traditions et folklore' => 'TraditionalCelebration',
    # '' => 'PilgrimageAndProcession',
    'Religieuse' => 'ReligiousEvent',
    # CulturalEvent
    'Culturelle' => 'CulturalEvent', # Generic
    # '' => 'Commemoration',
    'Musique' => 'Concert',
    'Visites - Patrimoine - Conférences' => %w[Conference Other], # FIXME: Other
    # '' => 'ArtistSigning',
    'Pour les enfants' => 'ChildrensEvent',
    'Expositions' => 'Exhibition',
    'Festivals' => 'Festival',
    # '' => 'Reading',
    # '' => 'Opera',
    'Spectacles, musique, théâtre' => %w[TheaterEvent Recital ShowEvent],
    # '' => 'ScreeningEvent',
    'Son et Lumière' => 'VisualArtsEvent',
    # '' => 'CircusEvent',
    'Danse' => 'DanceEvent',
    # '' => 'Harvest',
    # SportsEvent
    'Sports et loisirs' => 'SportsEvent', # Generic
    'Manifestations sportives' => 'SportsCompetition',
    # '' => 'SportsDemonstration',
    # '' => 'Game',
    # '' => 'Rally',
    'Randonnée' => 'Rambling',
    'Balade accompagnée' => 'Rambling',

    # Other. Not part of datatourisme ontology
    'Grands événements' => 'Other', # FIXME
    'Insolite' => 'Other', # FIXME
    'Manifestations nautiques et maritimes' => 'Other', # FIXME
    'Nature et détente' => 'Other', # FIXME
    'Sortie nature' => 'Other', # FIXME
  }

  @@bool = HashExcep[{
    nil => nil,
    'oui' => 'yes',
    'non' => 'no',
  }]

  @@wifi = HashExcep[{
    nil => nil,
    'Wifi' => 'wlan',
    'WIFI' => 'wlan',
    'Wifi gratuit' => 'wlan',
    'Wifi#Wifi' => 'wlan',
  }]

  def each(&block)
    if ENV['NO_DATA']
      loop([], &block)
    else
      features = self.class.fetch(@settings.client, @settings.syndication).collect{ |feat| [:feature, feat] }
      loop(features, &block)
    end
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat.last['Longitude'].to_f,
        feat.last['Latitude'].to_f
      ]
    }
  end

  def map_feature_tags(feat)
    r = feat

    date_debut = r['ObjectTypeName'] == 'Fêtes et manifestations' ? parse_dates(r['DateDebut']) : nil
    date_fin = r['ObjectTypeName'] == 'Fêtes et manifestations' ? parse_dates(r['DateFin']) : nil
    start_date = [date_debut&.at(0), date_fin&.at(0)].compact.min
    end_date = [date_debut&.at(1), date_fin&.at(1)].compact.max
    opening_hours = (date_debut&.at(2) || []).zip(date_fin&.at(2) || []).collect{ |dates|
      dates.compact.uniq.join('-')
    }.join(';')

    {
      name: { 'fr-FR' => r['NomOffre'] }.compact_blank,
      description: { 'fr-FR' => r['Descriptif'] }.compact_blank,
      website: multiple_split(r, %w[SiteWeb], 0),
      'website:details': { 'fr-FR' => @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID']) }.compact_blank,
      phone: multiple_split(r, %w[TelephoneFilaire TelephoneMobile], 0),
      image: multiple_split(r, %w[Photo], 0),
      addr: {
        street: [r['Adresse1'], r['Adresse2'], r['Adresse3']].compact_blank.join(', '),
        postcode: r['CP'],
        city: r['Commune'],
      }.compact_blank,
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && route(r)&.inject({
        gpx_trace: r['FichierGPX'],
        pdf: { 'fr-FR' => r['FichierPDF'] }.compact_blank,
      }, :merge)&.compact_blank,
      opening_hours: opening_hours,
      start_date: start_date,
      end_date: end_date,
      event: r['ObjectTypeName'] == 'Fêtes et manifestations' ? multiple_split(r, ['Type']).collect{ |t| [@@event_type[t]] }.flatten.compact : nil,
      wheelchair: @@bool[r['AccesPMR']],
      capacity: Integer(r['CapaciteHLOChambresHOTEmplacementsHPA'], exception: false),
      internet_access: @@wifi[r['WifiHLOHOTHPA']],
    }.merge(
      r['ObjectTypeName'] == 'Restauration' ? self.class.cuisines(multiple_split(r, ['Type'])) : {},
    )
  end
end
