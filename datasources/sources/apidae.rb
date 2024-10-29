# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'jsonpath'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


class ApidaeSource < Source
  class Settings < Source::SourceSettings
    const :projet_id, String, name: 'projetId'
    const :api_key, String, name: 'apiKey'
    const :selection_id, String
    const :website_details_url, T.nilable(String)
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def jp(object, path)
    JsonPath.on(object, "$.#{path}")
  end

  def self.build_url(path, query)
    query = CGI.escape(query.to_json)
    "https://api.apidae-tourisme.com/api/v002/#{path}/?query=#{query}"
  end

  def self.fetch(path, query)
    url = build_url(path, query)
    resp = HTTP.follow.get(url)
    if !resp.status.success?
      raise [url, resp].inspect
    end

    JSON.parse(resp.body)
  end

  def self.fetch_paged(path, query)
    first = 0
    count = 200 # Remote API max is 200

    query = query.merge({ first: first, count: count })
    next_url = T.let(
      build_url(path, query),
      T.nilable(String)
    )
    results = T.let([], T::Array[T.untyped])
    while next_url
      resp = HTTP.follow.get(next_url)
      if !resp.status.success?
        raise [next_url, resp].inspect
      end

      next_url = nil
      json = JSON.parse(resp.body)
      if json['objetsTouristiques']
        results += json['objetsTouristiques']
        first += count
        query = query.merge({ first: first, count: count })
        next_url = build_url(path, query)
      end
    end
    results
  end

  def i18n_keys(object)
    object&.transform_keys{ |key| key.gsub('libelle', '').downcase }
  end

  @@month = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]

  def self.date(date)
    month = @@month[date[5..6].to_i - 1]
    day = date[8..9]
    [month, day].join(' ')
  end

  @@days = {
    'LUNDI' => 'Mo',
    'MARDI' => 'Tu',
    'MERCREDI' => 'We',
    'JEUDI' => 'Th',
    'VENDREDI' => 'Fr',
    'SAMEDI' => 'Sa',
    'DIMANCHE' => 'Su',
  }

  @@day_month = {
    'D_1ER' => 1,
    'D_2EME' => 2,
    'D_3EME' => 3,
    'D_4EME' => 4,
    'D_DERNIER' => -1,
  }

  def self.openning_days(ojs)
    (ojs || []).collect{ |oj|
      @@days[oj['jour']] + (oj['jourDuMois'].nil? ? '' : "[#{@@day_month[oj['jourDuMois']]}]")
    }
  end

  @@exceptional_day = {
    'PREMIER_JANVIER' => 'Jan 1',
    'BERCHTOLDSTAG' => 'Jan 2', # Suisse
    'SAINT_JOSEPH' => 'Mar 19', # Suisse
    'VENDREDI_SAINT' => 'easter -2 day',
    'LUNDI_PAQUES' => 'easter +1 day',
    # 'ASCENSION' => '',
    # 'LUNDI_PENTECOTE' => '',
    'PREMIER_MAI' => 'May 1',
    'HUIT_MAI' => 'May 8',
    'QUATORZE_JUILLET' => 'Jul 14',
    # 'FETE_DIEU' => '', # Suisse
    'FETE_NATIONALE_SUISSE' => 'Aug 1', # Suisse
    'QUINZE_AOUT' => 'Aug 15',
    'LUNDI_DU_JEUNE_FEDERAL' => '', # Suisse
    'PREMIER_NOVEMBRE' => 'Nov 1',
    'ONZE_NOVEMBRE' => 'Nov 11',
    'IMMACULEE_CONCEPTION' => 'Dec 8', # Suisse
    'VINGT_CINQ_DECEMBRE' => 'Dec 25',
  }

  def self.exception_day(raw_date, day)
    if raw_date.nil?
      oed = @@exceptional_day[day]
      if oed.nil?
        logger.debug("Missing #{day}")
      else
        oed
      end
    else
      date(raw_date)
    end
  end

  def self.openning_hour(hour)
    hour[0..4]
  end

  def self.openning(ouverture)
    min_date_on = T.let(nil, T.nilable(String))
    max_date_off = T.let(nil, T.nilable(String))
    osm_openning_hours = (ouverture['periodesOuvertures'].collect { |po|
      min_date_on = [min_date_on, po['dateDebut']].compact.min
      max_date_off = po['tousLesAns'] ? nil : [max_date_off, po['dateFin']].compact.max

      date_on = po['dateDebut'] && date(po['dateDebut'])
      date_off = po['dateFin'] && date(po['dateFin'])
      date_off = nil if date_on == date_off
      date = [date_on, date_off].compact.join('-')

      days = (
        case po['type']
        when 'OUVERTURE_TOUS_LES_JOURS' then nil
        when 'OUVERTURE_SAUF' then (@@days.values - openning_days(po['ouverturesJournalieres'])).join(',')
        when 'OUVERTURE_SEMAINE' then openning_days(po['ouverturesJournalieres']).join(',')
        when 'OUVERTURE_MOIS' then openning_days(po['ouverturesJourDuMois']).join(',')
        else raise po['type']
        end
      )

      hour = (
        if po['horaireOuverture']
          openning_hour(po['horaireOuverture']) + (po['horaireFermeture'] ? "-#{openning_hour(po['horaireFermeture'])}" : '+')
        elsif po['horaireFermeture']
          "#{openning_hour(po['horaireFermeture'])}+"
        end
      )

      [[date, days, hour].compact.join(' ')] +
        (po['ouverturesExceptionnelles'] || {}).collect { |oe|
          exception_day(oe['dateOuverture'], oe['dateSpeciale'])
        }.compact.collect{ |day|
          [day, hour].compact.join(' ')
        }
    } + (ouverture['fermeturesExceptionnelles'] || {}).collect { |fe|
      exception_day(fe['dateFermeture'], fe['dateSpeciale'])
    }.compact.collect{ |day|
      "#{day} off"
    }).join(';')

    [min_date_on, max_date_off, osm_openning_hours]
  end

  # https://www.datatourisme.fr/ontology/core/#EntertainmentAndEvent
  @@event_type = HashExcep[{
    # SaleEvent
    'Manifestations commerciales' => 'SaleEvent', # Generic
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
    'Distractions et loisirs' => 'SocialEvent', # Generic
    # '' => 'LocalAnimation',
    # '' => 'Carnival',
    # '' => 'Parade',
    'Traditions et folklore' => 'TraditionalCelebration',
    # '' => 'PilgrimageAndProcession',
    # '' => 'ReligiousEvent',
    # CulturalEvent
    'Culture' => 'CulturalEvent', # Generic
    # '' => 'Concert',
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
    # '' => 'VisualArtsEvent',
    # '' => 'ShowEvent',
    # '' => 'CircusEvent',
    # '' => 'DanceEvent',
    # '' => 'Harvest',
    # SportsEvent
    'Sports' => 'SportsEvent', # Generic
    # '' => 'SportsCompetition',
    # '' => 'SportsDemonstration',
    # '' => 'Game',
    # '' => 'Rally',
    # '' => 'Rambling',

    # Other. Not part of datatourisme ontology
    'Nature et détente' => 'Other',
  }]

  def self.event(events)
    events.collect{ |tm|
      @@event_type[tm['libelleFr']]
    }.compact
  end

  @@practice = HashExcep[{
    # bicycle
    'Sports cyclistes' => nil, # Generic for bicycle and mtb
    'Itinéraire cyclo' => 'bicycle',
    'Itinéraire de VTT à Assistance Électrique' => 'bicycle',
    'Véloroute et voie verte' => 'bicycle',
    'Itinéraire de Vélo à Assistance Electrique' => 'bicycle',
    'Voie verte' => 'bicycle',
    'Véloroute' => 'bicycle',
    # mtb
    'Itinéraire VTT' => 'mtb',
    'Espace VTT' => 'mtb',
    # horse
    'Sports équestres' => 'horse', # Generic
    'Itinéraire de randonnée équestre' => 'horse',
    # hiking
    'Sports pédestres' => 'hiking', # Generic
    'Parcours d\'orientation' => 'hiking',
    'Itinéraire de randonnée pédestre' => 'hiking',
    'Parcours / sentier thématique' => 'hiking',
    'Itinéraire de Trail' => 'hiking',
    'Pôle trail' => 'hiking',
    # foot
    'Routes touristiques' => 'foot', # Generic
    'Jeu de piste / Chasse au trésor' => 'foot',
    # water
    'Sports d\'eau' => nil,
    'Itinéraire en canoë / en kayak' => 'canoe',
    # other random data
    'Parcours santé/obstacles' => 'fitness_trail',
    'Loisirs récréatifs' => nil,
    'Sports d\'adresse' => nil,
    'Paintball' => nil,
    'Golf' => nil,
    'Golf practice' => nil,
    'Golf 9 trous' => nil,
    'Golf 18 trous' => nil,
    'Laser game / Laser Tag' => nil,
    'Salle de jeux d\'arcade' => nil,
    'Sports divers' => nil,
  }]

  def self.practices(activites)
    activites.collect{ |activite|
      @@practice[activite['libelleFr']]
    }.compact.uniq
  end

  def self.classs(clas)
    clas = clas&.to_s
    return unless clas != '9'

    clas
  end

  def route(practices, feat)
    practices.to_h{ |practice_slug|
      [
        practice_slug,
        {
          # "difficulty":
          # 'informationsEquipement.itineraire.dureeJournaliere' will be removed at the end of 2025
          duration: jp(feat, 'informationsEquipement.itineraire.dureeJournaliere').first || jp(feat, 'ouverture.dureeSeance').first,
          length: jp(feat, 'informationsEquipement.itineraire.distance').first,
        }.compact_blank
      ]
    } || {}
  end

  def each
    if ENV['NO_DATA']
      []
    else
      super(self.class.fetch_paged('recherche/list-objets-touristiques', {
        projetId: @settings.projet_id,
        apiKey: @settings.api_key,
        selectionIds: [@settings.selection_id],
        responseFields: ['@default', 'gestion', 'ouverture', 'multimedias'], # '@all' for debug with all fields
      }))
    end
  end

  def select(feat)
    feat.dig('ouverture', 'fermeTemporairement') != 'FERME_TEMPORAIREMENT'
  end

  def map_id(feat)
    feat['identifier']
  end

  def map_updated_at(feat)
    feat.dig('gestion', 'dateModification')
  end

  def map_geometry(feat)
    feat.dig('localisation', 'geolocalisation', 'geoJson')
  end

  def map_tags(feat)
    r = feat
    date_on, date_off, osm_openning_hours = r.dig('ouverture', 'periodesOuvertures').nil? ? [] : self.class.openning(r['ouverture'])
    return nil if r['type'] == 'FETE_ET_MANIFESTATION' && date_on.nil? && date_off.nil?

    practices = self.class.practices(jp(r, 'informationsEquipement.activites[*]')) if jp(r, 'informationsEquipement.itineraire')&.compact_blank.present?
    {
      name: i18n_keys(r['nom']),
      description: i18n_keys(r.dig('presentation', 'descriptifCourt')),
      website: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Site web (URL)")].coordonnees.fr'),
      'website:details': { fr: @settings.website_details_url&.gsub('{{id}}', r['id'].to_s) }.compact_blank,
      phone: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Téléphone")].coordonnees.fr'),
      email: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Mél")].coordonnees.fr'),
      facebook: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Page facebook")].coordonnees.fr').first,
      image: jp(r, 'illustrations[*].traductionFichiers[0][?(@.locale=="fr")].urlDiaporama'),
      addr: {
        street: [
          r.dig('localisation', 'adresse', 'adresse1'),
          r.dig('localisation', 'adresse', 'adresse2'),
          r.dig('localisation', 'adresse', 'adresse3'),
        ].compact_blank.join(', '),
        postcode: r.dig('localisation', 'adresse', 'codePostal'),
        city: r.dig('localisation', 'adresse', 'commune', 'nom'),
        country: r.dig('localisation', 'adresse', 'commune', 'pays', 'libelleFr'),
      }.compact_blank,
      route: {
        gpx_trace: jp(r, 'multimedias[*].traductionFichiers[*][?(@.extension=="gpx")].url').first,
        pdf: practices.nil? ? nil : jp(r, 'multimedias[*].traductionFichiers[*][?(@.extension=="pdf")]').to_h{ |t| [t['locale'], t['url']] },
      }.merge(route(practices, r)).compact_blank,
      'capacity:persons': (jp(r, 'informationsHebergementLocatif.capacite.capaciteHebergement').first || jp(r, 'informationsHebergementLocatif.capacite.capaciteMaximumPossible').first)&.nonzero?,
      'capacity:rooms': (jp(r, 'informationsHebergementLocatif.capacite.nombreChambres').first || jp(r, 'informationsHotellerie.capacite.nombreChambresDeclareesHotelier').first)&.nonzero?,
      'capacity:beds': [jp(r, 'informationsHebergementLocatif.capacite.nombreLitsSimples').first, jp(r, 'informationsHebergementLocatif.capacite.nombreLitsDoubles').first].compact_blank.presence&.sum&.nonzero?,
      'capacity:pitches': jp(r, 'informationsHotelleriePleinAir.capacite.nombreEmplacementsClasses').first&.nonzero?,
      opening_hours: osm_openning_hours,
      start_date: r['type'] == 'FETE_ET_MANIFESTATION' ? date_on : nil,
      end_date: r['type'] == 'FETE_ET_MANIFESTATION' ? date_off : nil,
      stars: self.class.classs(
        r.dig('informationsHotellerie', 'classement', 'ordre') ||
        r.dig('informationsHebergementLocatif', 'classementPrefectoral', 'ordre') ||
        r.dig('informationsHotelleriePleinAir', 'classement', 'ordre')
      ),
      # event: r.dig('informationsFeteEtManifestation', 'typesManifestation').nil? ? nil : self.class.event(r.dig('informationsFeteEtManifestation', 'typesManifestation'))
    }
  end

  def map_native_properties(feat, properties)
    properties.transform_values{ |path|
      jp(feat, path)
    }.compact_blank
  end
end
