# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft'


class TourinsoftCdt50Source < TourinsoftSource
  def initialize(job_id, destination_id, settings)
    super(job_id, destination_id, settings)
    @photo_base_url = @settings['photo_base_url']
  end

  @@cuisines = HashExcep[{
    'Bistrot / bar à vin' => { amenity: 'restaurant', cuisine: ['bistro'] },
    'Bistrot gastronomique' => { amenity: 'restaurant', cuisine: ['bistronomique'] },
    'Brasserie' => { amenity: 'restaurant', cuisine: ['brasserie'] },
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
    'VTT' => 'mtb',
  }]

  @@difficulties = HashExcep[{
    nil => nil,
    'Facile' => 'easy',
    'Moyen' => 'normal',
    'Difficile' => 'hard',
  }]

  def route(feat)
    types = multiple_split(feat, ['Type'])
    length = (feat['LongueurKM']&.to_f || 0) * 1000
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

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat['Longitude'].to_f,
        feat['Latitude'].to_f
      ]
    }
  end

  def map_tags(feat)
    r = feat
    {
      name: { fr: r['NomOffre'] }.compact_blank,
      description: { fr: r['Descriptif'] }.compact_blank,
      website: multiple_split(r, %w[SiteWeb], 0),
      'website:details': { fr: @website_details_url&.gsub('{{id}}', r['SyndicObjectID']) }.compact_blank,
      phone: multiple_split(r, %w[TelephoneFilaire TelephoneMobile], 0),
      image: multiple_split(r, %w[Photo], 0)&.collect{ |p| "#{@photo_base_url}#{p}" },
      addr: {
        street: [r['Adresse1'], r['Adresse2'], r['Adresse3']].compact_blank.join(', '),
        postcode: r['CP'],
        city: r['Commune'],
      }.compact_blank,
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && route(r)&.inject({
        gpx_trace: r['FichierGPX'],
        pdf: { fr: r['FichierPDF'] }.compact_blank,
      }, :merge)&.compact_blank,
      start_date: r['ObjectTypeName'] == 'Fêtes et manifestations' && r['DateDebut']&.split('/')&.reverse&.join('-'),
      end_date: r['ObjectTypeName'] == 'Fêtes et manifestations' && r['DateFin']&.split('/')&.reverse&.join('-'),
      event: r['ObjectTypeName'] == 'Fêtes et manifestations' ? multiple_split(r, ['Type']).collect{ |t| [@@event_type[t]] }.flatten.compact : nil,
    }.merge(
      r['ObjectTypeName'] == 'Restauration' ? self.class.cuisines(multiple_split(r, ['Type'])) : {},
    )
  end
end
