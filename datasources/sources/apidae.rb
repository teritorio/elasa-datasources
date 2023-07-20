# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'jsonpath'
require 'open-uri'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


def jp(object, path)
  JsonPath.on(object, "$.#{path}")
end

class ApidaeSource < Source
  def initialize(job_id, destination_id, settings)
    super(job_id, destination_id, settings)
    @projet_id = @settings['projetId']
    @api_key = @settings['apiKey']
    @selection_id = @settings['selection_id']
    @website_details_url = @settings['website_details_url']
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
        puts "Missing #{day}"
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
    min_date_on = nil
    max_date_off = nil
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
    # other random data
    'Sports d\'adresse' => nil,
    'Paintball' => nil,
    'Golf' => nil,
    'Golf 18 trous' => nil,
  }]

  def self.practices(activites)
    activites.collect{ |activite|
      @@practice[activite['libelleFr']]
    }.compact.uniq
  end

  def each
    super(self.class.fetch_paged('recherche/list-objets-touristiques', {
      projetId: @projet_id,
      apiKey: @api_key,
      selectionIds: [@selection_id],
      responseFields: ['@default', 'gestion', 'ouverture', 'multimedias'], # '@all' for debug with all fields
    }))
  end

  def select(feat)
    feat['ouverture']['fermeTemporairement'] != 'FERME_TEMPORAIREMENT'
  end

  def map_id(feat)
    feat['identifier']
  end

  def map_updated_at(feat)
    feat['gestion']['dateModification']
  end

  def map_geometry(feat)
    feat['localisation']['geolocalisation']['geoJson']
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
      'website:details': { fr: @website_details_url&.gsub('{{id}}', r['id'].to_s) }.compact_blank,
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
        pdf: jp(r, 'multimedias[*].traductionFichiers[*][?(@.extension=="pdf")]').to_h{ |t| [t['locale'], t['url']] },
      }.merge(practices&.to_h{ |practice_slug|
        [
          practice_slug,
          {
            # "difficulty":
            duration: jp(r, 'informationsEquipement.itineraire.dureeJournaliere').first,
            length: jp(r, 'informationsEquipement.itineraire.distance').first,
          }.compact_blank
        ]
      } || {})&.compact_blank,
      opening_hours: osm_openning_hours,
      start_date: r['type'] == 'FETE_ET_MANIFESTATION' ? date_on : nil,
      end_date: r['type'] == 'FETE_ET_MANIFESTATION' ? date_off : nil,
      stars: r.dig('informationsHotellerie', 'classement', 'ordre')&.to_s,
      event: r.dig('informationsFeteEtManifestation', 'typesManifestation').nil? ? nil : self.class.event(r.dig('informationsFeteEtManifestation', 'typesManifestation'))
    }
  end
end
