# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft'


class TourinsoftSirtaquiSource < TourinsoftSource
  extend T::Sig

  class Settings < TourinsoftSource::Settings
    const :photo_base_url, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  @@cuisines = HashExcep[{
    # Cuisine
    'Burger' => { amenity: 'restaurant', cuisine: ['burger'] },
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
    'Cuisine sud-américaine' => { amenity: 'restaurant', cuisine: ['south_american'] },
    'Cuisine traditionnelle' => { amenity: 'restaurant' }, # FIXME: add specific tags
    # Diet
    'Cuisine bio' => { amenity: 'restaurant', organic: 'only' },
    'Cuisine diététique' => { amenity: 'restaurant' }, # FIXME: diet:*
    'Cuisine vegan' => { amenity: 'restaurant', 'diet:vegan': 'only' },
    'Cuisine végétarienne' => { amenity: 'restaurant', 'diet:vegetarian': 'only' },
    # Food
    'Nouvelle cuisine française' => { amenity: 'restaurant', cuisine: ['new_french'] },
    'Pizzas' => { amenity: 'restaurant', cuisine: ['pizza'] },
    'Poisson / fruits de mer' => { amenity: 'restaurant', cuisine: %w[fish seafood] },
    'Salades' => { amenity: 'fast_food', cuisine: ['salad'] },
    'Sandwichs' => { amenity: 'fast_food', cuisine: ['sandwich'] },
    'Tapas' => { amenity: 'restaurant', cuisine: ['tapas'] },
    'Tartes' => { amenity: 'restaurant', cuisine: ['pie'] },
    'Tartines' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Triperies' => { amenity: 'restaurant' }, # FIXME: add specific tags
    'Viandes' => { amenity: 'restaurant', cuisine: ['meat'] },
    # Non Restaurant
    'Glaces' => { amenity: 'ice_cream', cuisine: ['ice_cream'] },
    'Fromagerie' => { shop: 'cheese' },
  }]

  def self.cuisines(cuisines)
    cuisines.collect{ |cuisine|
      @@cuisines[cuisine]
    }.compact.inject(:deep_merge_array) || {}
  end

  @@class = HashExcep[{
    nil => nil,
    'Non classé' => nil,
    '1 étoile' => '1',
    '2 étoiles' => '2',
    '3 étoiles' => '3',
    '4 étoiles' => '4',
    '5 étoiles' => '5',
  }]

  def self.classs(clas)
    @@class[clas]
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
    'Dimanche Lundi' => '' ################ FIXME to be removed
  }]

  @@month = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]

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

    close_days = close_days&.split('-')&.collect{ |d| @@days[d] }
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

  def self.format_month_range(date_on, date_off)
    on = [@@month[date_on.split('-')[1].to_i - 1], date_on.split('-')[2]].compact.join(' ') if !date_on.nil?
    off = [@@month[date_off.split('-')[1].to_i - 1], date_off.split('-')[2]].compact.join(' ') if !date_off.nil? && date_on != date_off
    [on, off].compact.join('-')
  end

  def self.openning(ouvertures, openning_days)
    date_ons = []
    date_offs = []
    opennings = ouvertures.split('#').collect{ |ouverture|
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

      dates = format_month_range(date_on, date_off)

      days_hours = method(openning_days).call(parts[2..]&.collect(&:presence) || [])
      days_hours&.collect{ |days_hour|
        [dates, days_hour].compact.join(' ')
      }
    }.flatten(1)
    hours = opennings.join(';').presence
    if hours.nil?
      hours = format_month_range(date_ons.compact.min, date_offs.compact.max)
    end
    [date_ons.compact.min, date_offs.compact.max, hours]
  end

  @@practices = HashExcep[{
    'en canoë' => 'canoe',
    'à cheval' => 'horse',
    'à pied' => 'hiking',
    'à vélo' => 'bicycle',
    'à VAE' => 'bicycle',
    'à VTT' => 'mtb',
    'en voiture' => 'car',
  }]

  @@difficulties = HashExcep[{
    'Très facile' => 'easy',
    'Facile' => 'easy',
    'Moyenne' => 'normal',
    'Difficile' => 'hard',
    nil => nil,
  }]

  def route(itis, distance)
    distance &&= (distance.gsub(',', '.').to_f * 1000).to_i

    # "ITITEMPSDIF": "à pied|2h|Facile",
    itis&.split('#')&.collect{ |iti|
      practice, duration, difficulty = iti.split('|')

      practice_slug = @@practices[practice]

      duration_matches = duration.gsub(' ', '').downcase.match(/(?:([0-9]+)jours?)?(?:([0-9]+)h)?(?:([0-9]+).*)?/)
      duration_matches = duration_matches[1..].to_a.collect(&:to_i)
      duration = (duration_matches[0] * 24 + duration_matches[1]) * 60 + duration_matches[2]

      {
        "#{practice_slug}": {
          difficulty: @@difficulties[difficulty],
          duration: duration,
          length: distance,
        }.compact_blank
      }.compact_blank
    }
  end

  # https://www.datatourisme.fr/ontology/core/#EntertainmentAndEvent
  @@event_type = {
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
    # '' => 'Congress',
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
    # '' => 'CulturalEvent', # Culturelle, Generic
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
    # '' => 'ScreeningEvent',
    # '' => 'Recital',
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
  }

  def schema
    super.merge({
      i18n: {
        'route' => {
          'values' => @@practices.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr' => v } } }
        }
      }.merge(
        *@@practices.values.collect { |practice|
          {
            "route:#{practice}:difficulty" => {
              'values' => @@difficulties.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr' => v } } }
            }
          }
        }
      )
    })
  end

  def select(feat)
    super(feat) && !feat['PHOTO'].nil?
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat['LON'].to_f,
        feat['LAT'].to_f
      ]
    }
  end

  def pdfs(feat)
    feat.select{ |k, v|
      k.start_with?('DOCPDF') && !v.nil?
    }.to_h{ |k, _v|
      c = k[-2..].downcase
      [c == 'gb' ? 'en' : c, "#{@settings.photo_base_url}#{feat['DOCGPX']}"]
    }
  end

  def map_tags(feat)
    r = feat

    if r['OUVERTURECOMPLET']
      date_on, date_off, osm_openning_hours = self.class.openning(
        r['OUVERTURECOMPLET'],
        :openning_seven_days
      )
    elsif r['OUVERTURE'] || r['DATESCOMPLET']
      date_on, date_off, osm_openning_hours = self.class.openning(
        r['OUVERTURE'] || r['DATESCOMPLET'],
        :openning_one_days
      )
    end

    {
      ref: {
        'FR:CRTA': map_id(r),
      },
      name: { fr: r['NOMOFFRE'] }.compact_blank,
      description: { fr: r['DESCRIPTIF'] }.compact_blank,
      website: multiple_split(r, %w[URL URLCOMPLET], 0),
      'website:details': { fr: @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID']) }.compact_blank,
      phone: multiple_split(r, %w[TEL TELCOMPLET TELMOB TELMOBCOMPLET], 0),
      email: multiple_split(r, %w[MAIL MAILCOMPLET], 0),
      facebook: r['FACEBOOK'],
      twitter: r['TWITTER'],
      instagram: r['INSTAGRAM'],
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
      start_date: date_on,
      end_date: date_off,
      stars: self.class.classs(r['CLAS']),
      event: r['ObjectTypeName'] == 'Fêtes et manifestations' ? multiple_split(r, ['CATFMA']).collect{ |t| @@event_type[t] } : nil,
    }.merge(
      r['TYPE'] == 'Restaurant' ? self.class.cuisines(multiple_split(r, ['SPECIALITES'])) : {},
      r['TYPE']&.include?('Hôtel') ? { tourism: 'hotel' } : {},
    )
  end
end
