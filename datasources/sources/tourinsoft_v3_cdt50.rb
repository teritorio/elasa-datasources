# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft_v3'
require_relative 'tourinsoft_v3_helpers'


class TourinsoftV3Cdt50Source < TourinsoftV3Source
  extend T::Sig
  include TourinsoftV3Helpers

  class Settings < TourinsoftV3Source::Settings
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

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
    'Autre' => 'Other', # FIXME
  }

  @@bool = HashExcep[{
    nil => nil,
    true => 'yes',
    false => 'no',
  }]

  @@wifi = HashExcep[{
    nil => nil,
    'Wifi' => 'wlan',
    'WIFI' => 'wlan',
    'Wifi gratuit' => 'wlan',
    'Wifi payant' => 'wlan',
  }]

  def route(routes, distance)
    routes&.select{ |r| !r['Itineraireouvertauxpratiquessuivantes'].nil? }&.collect{ |r|
      practice = r['Itineraireouvertauxpratiquessuivantes']['ThesLibelle']
      duration = r['Dureeenheure']
      # distance = distance.gsub(',', '.').to_f
      difficulty = r['Difficulte'] && r['Difficulte']['ThesLibelle']

      practice_slug = @@practices[practice]

      if duration.present?
        d = duration.split(':', 2).collect(&:to_i)
        duration = d[0] * 60 + d[1]
      end

      {
        "#{practice_slug}": {
          difficulty: @@difficulties[difficulty],
          duration: duration,
          length: distance,
        }.compact_blank
      }.compact_blank
    }
  end

  def map_geometry(type_feat)
    _type, feat = type_feat
    {
      type: 'Point',
      coordinates: [
        feat['GmapLongitude'].to_f,
        feat['GmapLatitude'].to_f
      ]
    }
  end

  def pdfs(pdf)
    {
      'fr-FR' => pdf,
    }.compact_blank.presence
  end

  def map_feature_tags(feat)
    r = feat

    date_on, date_off, osm_openning_hours = openning(r['Datess'])

    id = map_id([nil, r])
    {
      # ref: {
      #   'FR:CRTA': id,
      # },
      name: { 'fr-FR' => r['SyndicObjectName'] }.compact_blank,
      description: { 'fr-FR' => r['DescriptifITI'] }.compact_blank,
      website: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Site web (URL)")]')&.pluck('CoordonneesTelecom')&.collect{ |url| valid_url(id, :website, url) }&.compact_blank,
      'website:details': { 'fr-FR' => valid_url(id, :'website:details', @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID'])) }.compact_blank,
      phone: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Téléphone filaire" || @.TypedaccesTelecom.ThesLibelle=="Téléphone cellulaire")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      email: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Mél")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      facebook: valid_url(id, :facebook, jp_first(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="UFacebook")].CoordonneesTelecom')),
      instagram: valid_url(id, :instagram, jp_first(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Instagram")].CoordonneesTelecom')),
      image: jp(r, '.Photos[*].Photo.Url'),
      addr: addr(r),
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && route(r['PratiqueDureeDifficultes'], r['LongueurKM'])&.inject({
        gpx_trace: jp_first(r, '.FichierGPXs[*].FichierGPX.Url'),
        pdf: pdfs(jp_first(r, '.FichierPDFs[*].FichierPDF.Url')),
      }, :merge)&.compact_blank,
      'capacity:pitches': r['EmplacementsHPA']&.to_i,
      opening_hours: osm_openning_hours,
      wheelchair: @@bool[r['AccesPMR']],
      capacity: r['CapaciteHLO']&.to_i,
      internet_access: @@wifi[jp_first_present(r, '.WifiCOMLOIHPAs[0].Services.ThesLibelle', '.WifiHOTs[0].Confortdelhotel[0].ThesLibelle')],
    }.merge(
        r['ObjectTypeName'] == 'Fêtes et manifestations' && {
          start_date: date_on,
          end_date: date_off,
          event: jp(r, '.Types[*].ThesLibelle').collect{ |t| @@event_type[t] }.uniq,
        } || {},
        r['ObjectTypeName'] == 'Restauration' ? self.class.cuisines(jp(r, '.TypeRESs[*].Categorie.ThesLibelle')) : {},
        r['ObjectTypeName'] == 'Hôtellerie' ? { tourism: 'hotel' } : {},
      )
  end
end
