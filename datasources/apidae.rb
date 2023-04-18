# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'jsonpath'
require 'open-uri'
require 'cgi'
require 'sorbet-runtime'


def jp(object, path)
  JsonPath.on(object, "$.#{path}")
end

# module Apidae
class Apidae
  def process(territoire_ids, projet_id, api_key, attribution)
    raw_json = fetch(territoire_ids, projet_id, api_key)
    objects = map(raw_json, attribution)
    { apidae: objects }
  end

  def build_url(territoire_ids, projet_id, api_key, first, count)
    query = CGI.escape({
      territoireIds: territoire_ids,
      projetId: projet_id,
      apiKey: api_key,
      first: first,
      count: count,
    }.to_json)
    "https://api.apidae-tourisme.com/api/v002/recherche/list-objets-touristiques/?query=#{query}"
  end

  def fetch(territoire_ids, projet_id, api_key)
    first = 0
    count = 200 # Remore API max is 200

    next_url = T.let(
      build_url(territoire_ids, projet_id, api_key, first, count),
      T.nilable(String)
    )
    results = T.let([], T::Array[T.untyped])
    while next_url
      puts "Fetch... #{first} #{next_url}"
      resp = HTTP.follow.get(next_url)
      if !resp.status.success?
        raise [next_url, resp].inspect
      end

      next_url = nil
      json = JSON.parse(resp.body)
      if json['objetsTouristiques']
        results += json['objetsTouristiques']
        next_url = (
            first += count
            build_url(territoire_ids, projet_id, api_key, first, count)
          )
      end
    end
    results
  end

  def i18n_keys(object)
    object&.transform_keys{ |key| key.gsub('libelle', '').downcase }
  end

  def map(raw_json, attribution)
    raw_json.select{ |r|
      r['localisation']['geolocalisation']['geoJson']
    }.map{ |r|
      {
        type: 'Feature',
        geometry: r['localisation']['geolocalisation']['geoJson'],
        properties: {
          id: r['identifier'],
          timestamp: r['update_datetime'],
          tags: {
            source: attribution,
            name: i18n_keys(r['nom']),
            descriptsion: i18n_keys(r.dig('presentation', 'descriptifCourt')),
            website: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Site web (URL)")].coordonnees.fr'),
            phone: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Téléphone")].coordonnees.fr'),
            email: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Mél")].coordonnees.fr'),
            facebook: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Page facebook")].coordonnees.fr'),
            image: jp(r, 'illustrations[*].traductionFichiers[0][?(@.locale=="fr")].urlDiaporama'),
            'contact:street': [
              r.dig('localisation', 'adresse', 'adresse1'),
              r.dig('localisation', 'adresse', 'adresse2'),
              r.dig('localisation', 'adresse', 'adresse3'),
            ].compact_blank.join(', '),
            'contact:postcode': r.dig('localisation', 'adresse', 'codePostal'),
            'contact:city': r.dig('localisation', 'adresse', 'commune', 'nom'),
            'contact:country': r.dig('localisation', 'adresse', 'commune', 'pays', 'libelleFr'),
          }.compact_blank
        }.compact_blank
      }
    }
  end
end
# end
