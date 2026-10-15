# frozen_string_literal: true
# typed: true

require 'uri'


module TourinsoftSirtaquiMixin
  CUISINES = HashExcep[{
    # Cuisine
    'Brunch' => { amenity: 'restaurant', cuisine: ['brunch'] },
    'Burger' => { amenity: 'restaurant', cuisine: ['burger'] },
    'Cuisine africaine' => { amenity: 'restaurant', cuisine: ['african'] },
    'Cuisine asiatique' => { amenity: 'restaurant', cuisine: ['asian'] },
    'Cuisine bistronomique' => { amenity: 'restaurant', cuisine: ['bistronomique'] },
    'Cuisine catalane' => { amenity: 'restaurant', cuisine: ['catalan'] },
    'Cuisine créole' => { amenity: 'restaurant', cuisine: ['regional'] },
    'Cuisine des Iles' => { amenity: 'restaurant', cuisine: ['caribbean'] },
    'Cuisine européenne' => { amenity: 'restaurant', cuisine: ['european'] },
    'Cuisine gastronomique' => { amenity: 'restaurant', cuisine: ['fine_dining'] },
    'Cuisine grillades' => { amenity: 'restaurant', cuisine: ['barbecue'] },
    'Cuisine indienne' => { amenity: 'restaurant', cuisine: ['indian'] },
    'Cuisine internationale' => { amenity: 'restaurant', cuisine: ['international'] },
    'Cuisine japonaise/sushi' => { amenity: 'restaurant', cuisine: %w[japanese sushi] },
    'Cuisine locavore' => { amenity: 'restaurant', cuisine: ['local'] },
    'Cuisine méditerranéenne' => { amenity: 'restaurant', cuisine: ['mediterranean'] },
    'Cuisine nord-américaine' => { amenity: 'restaurant', cuisine: ['american'] },
    'Cuisine orientale' => { amenity: 'restaurant', cuisine: ['oriental'] },
    'Cuisine rapide' => { amenity: 'fast_food' }, # FIXME: add specific tags
    'Cuisine régionale française' => { amenity: 'restaurant', cuisine: %w[regional french] },
    'Cuisine sud-américaine' => { amenity: 'restaurant', cuisine: ['south_american'] },
    'Cuisine traditionnelle' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Divers' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Régionales françaises' => { amenity: 'restaurant', cuisine: %w[regional french] },
    'Spécialités Locales' => { amenity: 'restaurant', cuisine: ['local'] },
    # Diet
    'Cuisine bio' => { amenity: 'restaurant', organic: 'only' },
    'Cuisine casher' => { amenity: 'restaurant', 'diet:kosher': 'only' },
    'Cuisine diététique' => { amenity: 'restaurant' }, # FIXME: diet:*
    'Cuisine hallal' => { amenity: 'restaurant', 'diet:halal': 'only' },
    'Cuisine sans gluten' => { amenity: 'restaurant', 'diet:gluten_free': 'only' },
    'Cuisine vegan' => { amenity: 'restaurant', 'diet:vegan': 'only' },
    'Cuisine végétarienne' => { amenity: 'restaurant', 'diet:vegetarian': 'only' },
    # Food
    'Crustacés' => { amenity: 'restaurant', cuisine: ['seafood'] },
    'Cuisine poissons' => { amenity: 'restaurant', cuisine: %w[fish seafood] },
    'Fruits de mer' => { amenity: 'restaurant', cuisine: ['seafood'] },
    'Nouvelle cuisine française' => { amenity: 'restaurant', cuisine: ['new_french'] },
    'Pâtes fraîches' => { amenity: 'restaurant', cuisine: ['pasta'] },
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
    # Non Restaurant
    'Fromage' => { shop: 'cheese' },
    'Fromagerie' => { shop: 'cheese' },
    'Glaces' => { amenity: 'ice_cream', cuisine: ['ice_cream'] },
    'Pâtisseries' => { shop: 'pastry' },
  }]

  def cuisines(cuisines)
    cuisines.collect{ |cuisine|
      CUISINES[cuisine]
    }.compact.inject(:deep_merge_array) || {}
  end

  CLASS = HashExcep[{
    nil => nil,
    'Non classé' => nil,
    'En cours de classement' => nil,
    '1 étoile' => '1',
    '2 étoiles' => '2',
    '3 étoiles' => '3',
    '4 étoiles' => '4',
    '5 étoiles' => '5',
    'Aire naturelle' => nil,
    'Parc résidentiel de loisirs classé' => nil,
  }]

  PRACTICES = HashExcep[{
    'en canoë' => 'canoe',
    'à cheval' => 'horse',
    'à pied' => 'hiking',
    'en course à pied' => 'running',
    'à vélo' => 'bicycle',
    'à VAE' => 'bicycle:electric',
    'à VTT' => 'mtb',
    'en gravel' => 'bicycle:gravel',
    'en voiture' => 'car',
  }]

  DIFFICULTIES = HashExcep[{
    'Très facile' => 'easy',
    'Facile' => 'easy',
    'Moyenne' => 'normal',
    'Difficile' => 'hard',
    'Très difficile' => 'hard',
    nil => nil,
  }]

  def route_duration(duration)
    duration_matches = duration.gsub(' ', '').downcase.match(/(?:([0-9]+)jours?)?(?:([0-9]+)h)?(?:([0-9]+).*)?/)
    duration_matches = duration_matches[1..].to_a.collect(&:to_i)
    (duration_matches[0] * 24 + duration_matches[1]) * 60 + duration_matches[2]
  end

  # https://www.datatourisme.fr/ontology/core/#EntertainmentAndEvent
  EVENT_TYPE = {
    # SaleEvent
    # '' => 'SaleEvent',
    'Brocante' => 'BricABrac',
    'Foire ou salon' => 'FairOrShow',
    'Marché' => 'Market',
    'Portes ouvertes' => 'OpenDay',
    'Vide greniers Braderie' => 'GarageSale',
    # BusinessEvent
    'Atelier/Stage' => 'TrainingWorkshop',
    # '' => 'ExecutiveBoardMeeting',
    'Conférence / Colloque' => 'Congress',
    # '' => 'BoardMeeting',
    # '' => 'WorkMeeting',
    # '' => 'Seminar',
    # SocialEvent
    # '' => 'SocialEvent', # Generic
    'Animations locales' => 'LocalAnimation',
    'Carnaval' => 'Carnival',
    'Défilé Cortège Parade' => 'Parade',
    # '' => 'TraditionalCelebration',
    # '' => 'PilgrimageAndProcession',
    'Évènement religieux' => 'ReligiousEvent',
    # CulturalEvent
    'Loisir culturel' => 'CulturalEvent', # Culturelle, Generic
    'Commémoration' => 'Commemoration',
    'Concert' => 'Concert',
    'Conférence' => 'Conference',
    # '' => 'ArtistSigning',
    'Animation Jeune Public' => 'ChildrensEvent',
    'Exposition' => 'Exhibition',
    'Festival' => 'Festival',
    # '' => 'Reading',
    'Opéra' => 'Opera',
    'Théâtre' => 'TheaterEvent',
    'Projection / Retransmission' => 'ScreeningEvent',
    'Récital' => 'Recital',
    # '' => 'VisualArtsEvent',
    'Spectacle' => 'ShowEvent',
    # '' => 'CircusEvent',
    # '' => 'DanceEvent', # Danse
    # '' => 'Harvest',
    # SportsEvent
    'Loisir sportif' => 'SportsEvent', # Generic
    'Compétition sportive' => 'SportsCompetition',
    # '' => 'SportsDemonstration',
    # '' => 'Game',
    'Rallye' => 'Rally',
    'Loisir nature' => 'Rambling', # FIXME: mapping to be checked

    # Other. Not part of datatourisme ontology
    'Animation patrimoine' => 'Other', # FIXME
    'Dégustations / Repas' => 'Other', # FIXME
    'Divertissement' => 'Other', # FIXME
    'Fête de ville, village, quartier' => 'Other', # FIXME
    'Meeting' => 'Other', # FIXME
    'Visite' => 'Other', # FIXME
    'Rendez-vous numérique' => 'Other', # FIXME
  }.freeze

  MONTH = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze

  FORMAT_MONTH_RANGE = lambda do |date_on, date_off|
    on = [MONTH[date_on.split('-')[1].to_i - 1], date_on.split('-')[2]].compact.join(' ') if !date_on.nil?
    off = [MONTH[date_off.split('-')[1].to_i - 1], date_off.split('-')[2]].compact.join(' ') if !date_off.nil? && date_on != date_off
    [on, off].compact.join('-')
  end
end
