# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft_v3'
require_relative 'tourinsoft_v3_helpers'


class TourinsoftV3CdtreunionSource < TourinsoftV3Source
  extend T::Sig
  include TourinsoftV3Helpers

  class Settings < TourinsoftV3Source::Settings
    const :gpx_trace_url, T.nilable(String)
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

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

  @@cuisines = HashExcep[{
    # Cuisine
    'Burger' => { amenity: 'restaurant', cuisine: ['burger'] },
    'Brunch' => { amenity: 'restaurant', cuisine: ['brunch'] },
    'Cuisine africaine' => { amenity: 'restaurant', cuisine: ['african'] },
    'Cuisine asiatique' => { amenity: 'restaurant', cuisine: ['asian'] },
    'Cuisine bistronomique' => { amenity: 'restaurant', cuisine: ['bistronomique'] },
    'Cuisine des Iles' => { amenity: 'restaurant', cuisine: ['caribbean'] },
    'Cuisine européenne' => { amenity: 'restaurant', cuisine: ['european'] },
    'Cuisine gastronomique' => { amenity: 'restaurant', cuisine: ['fine_dining'] },
    'Cuisine indienne' => { amenity: 'restaurant', cuisine: ['indian'] },
    'Cuisine japonaise/sushi' => { amenity: 'restaurant', cuisine: %w[japanese sushi] },
    'Cuisine locavore' => { amenity: 'restaurant', cuisine: ['local'] },
    'Cuisine méditerranéenne' => { amenity: 'restaurant', cuisine: ['mediterranean'] },
    'Cuisine nord-américaine' => { amenity: 'restaurant', cuisine: ['american'] },
    'Cuisine régionale française' => { amenity: 'restaurant', cuisine: %w[regional french] },
    'Cuisine créole' => { amenity: 'restaurant', cuisine: ['regional'] },
    'Cuisine sud-américaine' => { amenity: 'restaurant', cuisine: ['south_american'] },
    'Cuisine internationale' => { amenity: 'restaurant', cuisine: ['international'] },
    'Cuisine orientale' => { amenity: 'restaurant', cuisine: ['oriental'] },
    'Cuisine traditionnelle' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Cuisine rapide' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Divers' => { amenity: 'restaurant' }, # FIXME: add specific tags
    # Diet
    'Cuisine bio' => { amenity: 'restaurant', organic: 'only' },
    'Cuisine casher' => { amenity: 'restaurant', 'diet:kosher': 'only' },
    'Cuisine diététique' => { amenity: 'restaurant' }, # FIXME: diet:*
    'Cuisine vegan' => { amenity: 'restaurant', 'diet:vegan': 'only' },
    'Cuisine végétarienne' => { amenity: 'restaurant', 'diet:vegetarian': 'only' },
    'Cuisine sans gluten' => { amenity: 'restaurant', 'diet:gluten_free': 'only' },
    # Food
    'Nouvelle cuisine française' => { amenity: 'restaurant', cuisine: ['new_french'] },
    'Pizzas' => { amenity: 'restaurant', cuisine: ['pizza'] },
    'Poisson / fruits de mer' => { amenity: 'restaurant', cuisine: %w[fish seafood] },
    'Poisson' => { amenity: 'restaurant', cuisine: ['fish'] },
    'Salades' => { amenity: 'fast_food', cuisine: ['salad'] },
    'Sandwichs' => { amenity: 'fast_food', cuisine: ['sandwich'] },
    'Tapas' => { amenity: 'restaurant', cuisine: ['tapas'] },
    'Tartes' => { amenity: 'restaurant', cuisine: ['pie'] },
    'Tartines' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Triperies' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Viandes' => { amenity: 'restaurant', cuisine: ['meat'] },
    'Crustacés' => { amenity: 'restaurant', cuisine: ['seafood'] },
    # Non Restaurant
    'Glaces' => { amenity: 'ice_cream', cuisine: ['ice_cream'] },
    'Pâtisseries' => { shop: 'pastry' },
    'Fromagerie' => { shop: 'cheese' },
  }]

  def cuisines(cuisines)
    cuisines.collect{ |cuisine|
      @@cuisines[cuisine]
    }.compact.inject(:deep_merge_array) || {}
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

  def addr(feat)
    # return nil if feat.dig('Adresses', 0).nil?

    {
      street: [feat['Adresse1'], feat['Adresse1Suite'], feat['Adresse2'], feat['Adresse3']].compact_blank.join(', '),
      postcode: feat['CodePostal'] || feat['Codepostal'],
      city: feat['Commune'],
    }.compact_blank
  end

  def map_feature_tags(feat)
    r = feat

    _date_on, _date_off, osm_openning_hours = openning(r['PeriodeOuvertures'])

    id = map_id([nil, r])
    {
      ref: {
        'FR:CRT974': id,
        'FR:SIRET': r['SIRET'],
      }.compact_blank,
      name: { 'fr-FR' => r['SyndicObjectName'] }.compact_blank,
      description: { 'fr-FR' => jp_first(r, '.Descriptifss[*].Descriptioncommerciale') }.compact_blank,
      website: jp(r, '.Moyencommunications[*][?(@.Moyendecommunication.ThesLibelle=="Site web (url)")]')&.pluck('Coordonnees')&.collect{ |url| valid_url(id, :website, url) }&.compact_blank,
      'website:details': { 'fr-FR' => valid_url(id, :'website:details', @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID'])) }.compact_blank,
      phone: jp(r, '.Moyencommunications[*][?(@.Moyendecommunication.ThesLibelle=="Tél. fixe" || @.Moyendecommunication.ThesLibelle=="Tél. mobile")]')&.pluck('Coordonnees')&.compact_blank,
      email: jp(r, '.Moyencommunications[*][?(@.Moyendecommunication.ThesLibelle=="Mail")]')&.pluck('Coordonnees')&.compact_blank,
      facebook: valid_url(id, :facebook, jp_first(r, '.Reseauxsociauxs[*][?(@.Typedeplateforme.ThesLibelle=="Facebook")].URL')),
      twitter: valid_url(id, :twitter, jp_first(r, '.Reseauxsociauxs[*][?(@.Typedeplateforme.ThesLibelle=="Twitter")].URL')),
      instagram: valid_url(id, :instagram, jp_first(r, '.Reseauxsociauxs[*][?(@.Typedeplateforme.ThesLibelle=="Instagram")].URL')),

      image: jp(r, '.Photos[*].Photo.Url'),
      addr: addr(r),
      'capacity:beds': jp_first(r, '.Capacites[*].Nombredelits')&.to_i,
      'capacity:rooms': jp_first(r, '.Capacites[*].Nombretotaldechambres')&.to_i,
      'capacity:persons': jp_first(r, '.Capacites[*].Capacitetotalenombredepersonnes')&.to_i,
      opening_hours: osm_openning_hours,
      stars: ['Hébergements locatifs', 'Hôtellerie', 'Hôtellerie de plein air', 'Résidences'].include?(r['ObjectTypeName']) ? @@stars[r['ClassementPrefectoral']] : nil,
      # internet_access: jp(r, '.Servicess[*][?(@.ThesLibelle=="Wifi")]').any? ? 'wlan' : nil,
      # pets: { true => 'yes', false => 'no' }[r['Animaux']]
    }.merge(
        r['ObjectTypeName'] == 'Restauration' ? cuisines(jp(r, '.Typecuisines[*].ThesLibelle')) : {},
        r['ObjectTypeName'] == 'Hôtellerie' ? { tourism: 'hotel' } : {},
      )
  end
end
