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
    'Brasserie' => { amenity: 'restaurant', cuisine: ['brasserie'] },
    'Café' => { amenity: 'cafe' },
    'Cafétéria' => { amenity: 'fast_food', fast_food: 'cafeteria' },
    'Crêperie' => { amenity: 'restaurant', cuisine: ['crepe'] },
    'Cuisine inventive' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Cuisine traditionnelle' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Cuisine traditionnelle française' => { amenity: 'restaurant', cuisine: ['french'] },
    'Grill' => { amenity: 'restaurant', cuisine: ['grill'] },
    'Pizzeria' => { amenity: 'restaurant', cuisine: ['pizza'] },
    'Restauration à thème' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Restauration Rapide' => { amenity: 'fast_food' },
    'Rôtisserie' => { amenity: 'restaurant', cuisine: ['rotisserie'] },
    'Routier' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Saladerie' => { amenity: 'fast_food', cuisine: ['salad'] },
    'Salon de thé' => { amenity: 'cafe', cuisine: ['tea'] },
  }]

  def self.cuisines(cuisines)
    cuisines.collect{ |cuisine|
      @@cuisines[cuisine]
    }.compact.inject(:deep_merge_array) || {}
  end

  @@practices = HashExcep[{
    'Pédestre' => 'hiking',
  }]

  def self.route(route)
    practice_slug = @@practices[route]
    {
      "#{practice_slug}": {
        length: 0, # FIXME
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
      website: multiple_split(r, %w[SiteWeb], 0),
      'website:details': { fr: @website_details_url&.gsub('{{id}}', r['SyndicObjectID']) }.compact_blank,
      phone: multiple_split(r, %w[TelephoneFilaire TelephoneMobile], 0),
      image: multiple_split(r, %w[Photo], 0)&.collect{ |p| "#{@photo_base_url}#{p}" },
      addr: {
        street: [r['Adresse1'], r['Adresse2'], r['Adresse3']].compact_blank.join(', '),
        postcode: r['CP'],
        city: r['Commune'],
      }.compact_blank,
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && multiple_split(r, ['Type']).collect{ |route| self.class.route(route) }&.inject({
        gpx_trace: r['FichierGPX']
      }, :merge)&.compact_blank,
      start_date: r['ObjectTypeName'] == 'Fêtes et manifestations' && r['DateDebut']&.split('/')&.reverse&.join('-'),
      end_date: r['ObjectTypeName'] == 'Fêtes et manifestations' && r['DateFin']&.split('/')&.reverse&.join('-'),
      event: r['ObjectTypeName'] == 'Fêtes et manifestations' ? multiple_split(r, ['Type']).collect{ |t| [@@event_type[t]] }.flatten : nil,
    }.merge(
      r['ObjectTypeName'] == 'Restauration' ? self.class.cuisines(multiple_split(r, ['Type'])) : {},
    )
  end
end
