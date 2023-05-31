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
  def initialize(source_id, attribution, settings, path)
    super(source_id, attribution, settings, path)
    @projet_id = settings['projetId']
    @api_key = settings['apiKey']
    @selection_id = settings['selection_id']
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
    count = 200 # Remore API max is 200

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

  def each
    raw = self.class.fetch_paged('recherche/list-objets-touristiques', {
      projetId: @projet_id,
      apiKey: @api_key,
      selectionIds: [@selection_id],
    })
    puts "#{self.class.name}: #{raw.size}"

    raw.select{ |r|
      r['localisation']['geolocalisation']['geoJson']
    }.each{ |r|
      yield ({
        type: 'Feature',
        geometry: r['localisation']['geolocalisation']['geoJson'],
        properties: {
          id: r['identifier'],
          updated_at: r['update_datetime'],
          source: @attribution,
          tags: {
            name: i18n_keys(r['nom']),
            description: i18n_keys(r.dig('presentation', 'descriptifCourt')),
            website: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Site web (URL)")].coordonnees.fr'),
            phone: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Téléphone")].coordonnees.fr'),
            email: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Mél")].coordonnees.fr'),
            facebook: jp(r, 'informations.moyensCommunication[*][?(@.type.libelleFr=="Page facebook")].coordonnees.fr'),
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
            },
          }.compact_blank
        }.compact_blank
      })
    }
  end
end
