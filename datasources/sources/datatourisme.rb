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
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } }

  def self.fetch(path)
    url = "https://diffuseur.datatourisme.fr/webservice/#{path}"
    response = HTTP.follow.get(url)

    logger.info(response.headers['Content-Type'])

    return unless response.status.success?

    binary_data = response.body
    decoded_data = decompress_gzip(binary_data)

    jsonld = JSON.parse(decoded_data)

    logger.info(jsonld)
    jsonld.dig('results', 'bindings')
  end

  def self.decompress_zip(data)
    decompressed_data = nil
    Zip::InputStream.open(StringIO.new(data)) do |zip|
      logger.info("Unzipping #{zip.entries.size} files")
      while (entry = zip.get_next_entry)
        decompressed_data = entry.get_input_stream.read
      end
    end
    decompressed_data
  end

  def self.decompress_gzip(data)
    Zlib::GzipReader.new(StringIO.new(data)).read
  end

  def self.read_from(file_path)
    jsonld = JSON.parse(File.read(file_path))
    jsonld.dig('results', 'bindings')
  end

  def each(datas)
    if ENV['NO_DATA']
      []
    else
      super
    end
  end

  def map_destination_id(feat)
    "#{feat['identifier']}-#{feat['publisher_name']}"
  end

  def map_updated_at(_feat)
    Time.now.to_s
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [feat['Longitude'].to_f, feat['Latitude'].to_f],
    }
  end

  def map_tags(feat)
    {
      'name' => { 'fr' => feat['publisher_name'] },
      'addr' => {
        'street' => feat['street_address'],
        'postcode' => feat['postalcode_address'],
        'city' => feat['city_address'],
      },
    }
  end

  def map_id(feat)
    feat['identifier']
  end
end

# requête SPARQL pour récupérer les données de Datatourisme
_sparql = <<~SPARQL
    PREFIX dt: <https://www.datatourisme.fr/ontology/core>
    PREFIX schema: <http://schema.org>
    PREFIX purl: <http://purl.org/dc/elements/1.1>

    SELECT
      ?publisher_name ?identifier
      ?elem ?type ?label
      ?Latitude ?Longitude ?street_address ?postalcode_address ?city_address
      ?wheelchair ?takeaway ?contact_phone ?contact_email ?contact_website
    WHERE {
      ?elem <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> ?type;
          <http://www.w3.org/2000/01/rdf-schema#label> ?label;
          dt:isLocatedAt ?location.
      FILTER (?type IN (
        dt:Camping,
        dt:Church,
        dt:Restaurant,
        dt:LocalTouristOffice,
        dt:Museum,
        dt:PointOfView,
        dt:PicnicArea,
    end

  # requête SPARQL pour récupérer les données de Datatourisme
  _sparql = <<~SPARQL
    PREFIX dt: <https://www.datatourisme.fr/ontology/core>
    PREFIX schema: <http://schema.org>
    PREFIX purl: <http://purl.org/dc/elements/1.1>

    SELECT
      ?publisher_name ?identifier
      ?elem ?type ?label
      ?Latitude ?Longitude ?street_address ?postalcode_address ?city_address
      ?wheelchair ?takeaway ?contact_phone ?contact_email ?contact_website
    WHERE {
      ?elem <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> ?type;
          <http://www.w3.org/2000/01/rdf-schema#label> ?label;
          dt:isLocatedAt ?location.
      FILTER (?type IN (
        dt:Camping,
        dt:Church,
        dt:Restaurant,
        dt:LocalTouristOffice,
        dt:Museum,
        dt:PointOfView,
        dt:PicnicArea,
        dt:WineCellar
      )).
      ?location schema:geo ?geo.
      ?geo schema:latitude ?Latitude;
          schema:longitude ?Longitude.
      ?location schema:address ?address.
      ?address schema:streetAddress ?street_address;
              schema:postalCode ?postalcode_address;
              schema:addressLocality ?city_address.
      OPTIONAL {
        ?elem dt:hasBeenPublishedBy ?publisher.
        ?publisher schema:legalName ?publisher_name.
      }
      OPTIONAL {
        ?elem purl:identifier ?identifier.
      }
      OPTIONAL {
        ?elem dt:hasBookingContact ?agent_contact.
        ?agent_contact schema:telephone ?contact_phone.
      }
      OPTIONAL {
        ?elem dt:hasBookingContact ?agent_contact.
        ?agent_contact schema:email ?contact_email.
      }
      OPTIONAL {
        ?elem dt:hasBookingContact ?agent_contact.
        ?agent_contact <http://xmlns.com/foaf/0.1/homepage> ?contact_website.
      }
      OPTIONAL {
        ?elem dt:reducedMobilityAccess ?wheelchair.
      }
      OPTIONAL {
        ?elem dt:takeAway ?takeaway.
      }
    }
SPARQL
