# frozen_string_literal: true
# typed: true

require 'active_support/all'
require 'cgi'
require 'http'
require 'json'
require 'sorbet-runtime'
require 'stringio'
require 'zip'
require 'zlib'

require_relative 'source'

class DatatourismeSource < Source
  class Settings < Source::SourceSettings
    const :key, String, name: 'key' # API key
    const :flow_key, String, name: 'flow_key' # Flow key
    const :destination_id, T.nilable(String), name: 'destination_id' # Destination ID
    const :datas, T.nilable(T::Array[T::Hash[String, T.untyped]]), name: 'datas' # Datas
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } }

  def self.fetch(path)
    url = "https://diffuseur.datatourisme.fr/webservice/#{path}"
    response = HTTP.follow.get(url)

    return [url, response].inspect unless response.status.success?

    Set.new(JSON.parse(
      decompress_gzip(response.body.to_s)
    )['results']['bindings']).to_a
  end

  def self.decompress_gzip(data)
    Zlib::GzipReader.new(StringIO.new(data)).read
  end

  def each
    if ENV['NO_DATA']
      []
    else
      super(@settings.datas)
    end
  end

  def map_updated_at(feat)
    feat.dig('updated_at', 'value')
  end

  def map_source(feat)
    feat.dig('type', 'value').split('#').last
  end

  def map_destination_id(_feat)
    @settings.destination_id
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [feat.dig('Longitude', 'value')&.to_f, feat.dig('Latitude', 'value')&.to_f],
    }
  end

  def map_tags(feat)
    {
      'name' => {
        'fr' => feat.dig('label', 'value'),
      },
      'addr' => {
        'street' => feat.dig('street_address', 'value') || '',
        'postcode' => feat.dig('postalcode_address', 'value') || '',
        'city' => feat.dig('city_address', 'value') || '',
        'country' => feat.dig('country_address', 'value') || '',
      },
      'email' => [feat.dig('contact_email', 'value')].compact,
      'phone' => [feat.dig('contact_phone', 'value')].compact,
      'website' => [feat.dig('contact_website', 'value')].compact,
      'wheelchair' => [feat.dig('wheelchair', 'value')].compact,
      'image' => [feat.dig('image', 'value')].compact,
      'description' => [feat.dig('description', 'value')].compact,
    }
  end

  def map_id(feat)
    feat.dig('identifier', 'value')
  end
end

# requête SPARQL pour récupérer les données de Datatourisme
_sparql = <<~SPARQL
  PREFIX : <https://www.datatourisme.fr/ontology/core#>
  PREFIX dc: <http://purl.org/dc/elements/1.1/>
  PREFIX schema: <http://schema.org/>
  PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  PREFIX ebucore: <http://www.ebu.ch/metadata/ontologies/ebucore/ebucore#>
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>

  SELECT ?identifier ?type ?label
      ?email ?full_name ?Latitude ?Longitude
      ?street_address ?postalcode_address ?city_address ?updated_at
      ?publisher_name ?contact_phone
      ?contact_email ?wheelchair ?image ?contact_website ?description
  WHERE {
    ?elem rdf:type ?type;
      dc:identifier ?identifier;
      rdfs:label ?label;
      :isLocatedAt ?location;
      :lastUpdate ?updated_at;
    FILTER (?type IN (
      :Place,
      :Camping,
      :Church,
      :Restaurant,
      :LocalTouristOffice,
      :Museum,
      :PointOfView,
      :PicnicArea,
      :WineCellar
    )).
    ?location schema:geo ?geo.
    ?geo schema:latitude ?Latitude;
        schema:longitude ?Longitude.
    ?location schema:address ?address.
    ?address schema:streetAddress ?street_address;
        schema:postalCode ?postalcode_address;
        schema:addressLocality ?city_address.
    OPTIONAL {
        ?elem :hasBeenPublishedBy ?publisher.
        ?publisher schema:legalName ?publisher_name.
    }
    OPTIONAL {
        ?elem :hasContact ?agent_contact.
        ?agent_contact schema:telephone ?phone.
    }

    # Get only one data for phone, email and image instead of multiple (array of data)
    OPTIONAL {
        ?elem :hasBookingContact ?agent_contact.
        ?agent_contact schema:telephone ?phone.
    }
    OPTIONAL {
        ?elem :hasContact ?agent_contact.
        ?agent_contact schema:email ?email.
    }
    OPTIONAL {
        ?elem :hasBookingContact ?agent_contact.
        ?agent_contact schema:email ?email.
    }
    OPTIONAL {
        ?elem :hasBookingContact ?agent_contact.
        ?agent_contact foaf:homepage ?contact_website.
    }
    OPTIONAL {
        ?elem :shortDescription ?description.
    }
    OPTIONAL {
      ?elem :reducedMobilityAccess ?wheelchair.
    }
    OPTIONAL {
      ?elem :hasRepresentation ?representation.
      ?representation ebucore:hasRelatedResource ?relatedResource.
      ?relatedResource ebucore:locator ?image.
    }
  }
SPARQL
