# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft_v3'


class TourinsoftV3Cdt66Source < TourinsoftV3Source
  extend T::Sig

  class Settings < TourinsoftV3Source::Settings
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

  @@stars = HashExcep[{
    nil => nil,
    'Non classé' => nil,
    'Non Classé' => nil,
    '1 étoile' => '1',
    '2 étoiles' => '2',
    '3 étoiles' => '3',
    '4 étoiles' => '4',
    '5 étoiles' => '5',
  }]

  @@practices = HashExcep[{
    'Pédestre' => 'hiking',
    "Parcours d'orientation" => 'hiking',
    'Cyclotouriste' => 'bicycle',
    'VTT' => 'mtb',
    nil => nil,
  }]

  @@difficulties = HashExcep[{
    'Très facile' => 'easy',
    'Facile' => 'easy',
    'Moyen' => 'normal',
    'Difficile' => 'hard',
    'Très difficile' => 'hard',
    nil => nil,
  }]

  # https://www.datatourisme.fr/ontology/core/#EntertainmentAndEvent
  @@event_type = {
    # SaleEvent
    # '' => 'SaleEvent',
    # '' => 'BricABrac',
    'Braderie' => 'FairOrShow',
    'Foire' => 'FairOrShow',
    'Marché' => 'Market',
    'Portes ouvertes' => 'OpenDay',
    'Vide-grenier' => 'GarageSale',
    # BusinessEvent
    'Stage / Atelier' => 'TrainingWorkshop',
    # '' => 'ExecutiveBoardMeeting',
    # '' => 'Congress',
    # '' => 'BoardMeeting',
    # '' => 'WorkMeeting',
    # '' => 'Seminar',
    # SocialEvent
    'Action citoyenne' => 'SocialEvent', # Generic
    'Bal' => 'LocalAnimation',
    # '' => 'Carnival',
    'Défilé Cortège Parade' => 'Parade',
    # '' => 'TraditionalCelebration',
    # '' => 'PilgrimageAndProcession',
    # '' => 'ReligiousEvent',
    # CulturalEvent
    'Aplec' => 'CulturalEvent', # Generic
    'Commémoration' => 'Commemoration',
    'Concert' => 'Concert',
    'Débat / Conférence' => 'Conference',
    # '' => 'ArtistSigning',
    # '' => 'ChildrensEvent',
    'Exposition' => 'Exhibition',
    'Festival' => 'Festival',
    # '' => 'Reading',
    # '' => 'Opera',
    'Théâtre' => 'TheaterEvent',
    'Projection, cinéma' => 'ScreeningEvent',
    # '' => 'Recital',
    'Feux d\'artifice' => 'VisualArtsEvent',
    'Repas spectacle' => 'ShowEvent',
    'Spectacle' => 'ShowEvent',
    # '' => 'CircusEvent',
    # '' => 'DanceEvent', # Danse
    # '' => 'Harvest',
    # SportsEvent
    'Manifestation sportive' => 'SportsEvent', # Generic
    'Pratique sportive encadrée' => 'SportsEvent', # Generic
    'Compétition' => 'SportsCompetition',
    'Trail' => 'SportsCompetition',
    # '' => 'SportsDemonstration',
    'Concours' => 'Game',
    'Jeux' => 'Game',
    'Rifles' => 'Game',
    'Rallye' => 'Rally',
    'Randonnée, balade' => 'Rambling',

    # Other. Not part of datatourisme ontology
    'Rassemblement / réunion' => 'Other', # FIXME
    'Thé dansants' => 'Other', # FIXME
    'Visite guidée' => 'Other', # FIXME
  }

  def route_duration(duration)
    duration.split(':').map(&:to_i).then { |h, m, _s| h * 60 + m }
  end

  def route(feat)
    r = feat
    practice = r['Type'] && r['Type']['ThesLibelle']
    duration = r['Duree']
    distance = r['Distance']
    difficulty = r['Difficulte'] && r['Difficulte']['ThesLibelle']

    practice_slug = @@practices[practice]
    duration = route_duration(duration) if !duration.nil?

    {
      "#{practice_slug}": {
        difficulty: @@difficulties[difficulty],
        duration: duration,
        length: distance,
      }.compact_blank
    }.compact_blank
  end

  def map_geometry(feat)
    if feat['ObjectTypeName'] == 'Itinéraires touristiques' && !feat.dig('Traces', 0, 'Itinerairegooglemap').nil?
      trace = JSON.parse(feat.dig('Traces', 0, 'Itinerairegooglemap'))
      path = trace['lignes']
        .map { |l| l['path'] }
        .flatten(1)
        .map { |lat, lon, *_| [lon, lat] }
        .inject([]) { |acc, x| acc.last == x ? acc : acc << x }

      {
        type: 'LineString',
        coordinates: path
      }
    else
      {
        type: 'Point',
        coordinates: [
          feat['GmapLongitude'].to_f,
          feat['GmapLatitude'].to_f
        ]
      }
    end
  end

  def addr(feat)
    return nil if feat.dig('Adresses', 0).nil?

    {
      street: [feat['Adresses'][0]['Adresse1'], feat['Adresses'][0]['Adresse1Suite'], feat['Adresses'][0]['Adresse2'], feat['Adresses'][0]['Adresse3']].compact_blank.join(', '),
      postcode: feat['Adresses'][0]['CodePostal'] || feat['Adresses'][0]['Codepostal'],
      city: feat['Adresses'][0]['Commune'],
    }.compact_blank
  end

  def openning(dates)
    return nil if dates.blank? || !dates.is_a?(Array)

    valid_dates = dates.select { |d|
      d.is_a?(Hash) && d['Datedebut'] && d['Datefin']
    }

    return nil if valid_dates.empty?

    date_on = valid_dates.map { |d| d['Datedebut'][0, 10] }.min
    date_off = valid_dates.map { |d| d['Datefin'][0, 10] }.max

    [date_on, date_off]
  end

  def map_tags(feat)
    r = feat

    date_on, date_off = openning(r['Dates'])

    id = map_id(r)
    {
      ref: {
        'FR:CRTA': id,
      },
      name: { 'fr-FR' => r['SyndicObjectName'] }.compact_blank,
      # description: { 'fr-FR' => jp_first(r, '.DescriptionsCommercialess[*].Descriptioncommerciale') }.compact_blank,
      website: jp(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="Site web")]')&.pluck('CoordonneesTelecom')&.collect{ |url| valid_url(id, :website, url) }&.compact_blank,
      'website:details': { 'fr-FR' => valid_url(id, :'website:details', @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID'])) }.compact_blank,
      phone: jp(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="Téléphone fixe" || @.TypedaccesTelecom.ThesLibelle=="Portable")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      email: jp(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="Mail")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      facebook: valid_url(id, :facebook, jp_first(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="URL Facebook")].CoordonneesTelecom')),
      twitter: valid_url(id, :twitter, jp_first(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="URL Twitter")].CoordonneesTelecom')),
      instagram: valid_url(id, :instagram, jp_first(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="URL Instagram")].CoordonneesTelecom')),
      # youtube: jp_first(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="Chaine Youtube")].CoordonneesTelecom'),
      # tiktok: jp_first(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="Url TikTok")].CoordonneesTelecom'),
      # tripadvisor: jp_first(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="URL TripAdvisor")].CoordonneesTelecom'),
      # googleavis: jp_first(r, '.Contacts[*][?(@.TypedaccesTelecom.ThesLibelle=="URL Google Avis")].CoordonneesTelecom'),
      image: jp(r, '.Photos[*].Photo.Url'),
      addr: addr(r),
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && route(r)&.compact_blank,
      # opening_hours: osm_openning_hours,
      stars: ['Hébergements locatifs', 'Hôtellerie', 'Hôtellerie de plein air', 'Résidences'].include?(r['ObjectTypeName']) ? @@stars[r.dig('Classement', 'ThesLibelle')] : nil,
      internet_access: jp(r, '.Servicess[*][?(@.ThesLibelle=="Wifi")]').any? ? 'wlan' : nil,
    }.merge(
        r['ObjectTypeName'] == 'Fêtes et manifestations' && {
          start_date: date_on,
          end_date: date_off,
          event: jp(r, '.Types[*].ThesLibelle').collect{ |t| @@event_type[t] }.uniq,
        } || {},
        # r['ObjectTypeName'] == 'Restauration' ? cuisines(jp(r, '.ClassificationTypeCuisines[*].ThesLibelle')) : {},
        r['ObjectTypeName'] == 'Hôtellerie' ? { tourism: 'hotel' } : {},
      )
  end
end
