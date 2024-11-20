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
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } }

  def self.fetch(path)
    url = "https://diffuseur.datatourisme.fr/webservice/#{path}"
    logger.info("Fetching #{url}")
    response = HTTP.follow.get(url)

    logger.info("Response: #{response.status}")

    return [url, response].inspect unless response.status.success?

    binary_data = response.body.to_s
    decompressed_data = decompress_gzip(binary_data)

    process_zip(decompressed_data)
  end

  def self.process_zip(data)
    results = []
    Zip::File.open_buffer(StringIO.new(data)) do |zip|
      zip.each_with_index do |entry, index|
        data = entry.get_input_stream.read
        decompressed_data = data
        results << JSON.parse(decompressed_data)
        if index == 10
          break
        end
      end
    end

    results
  end

  def self.decompress_gzip(data)
    Zlib::GzipReader.new(StringIO.new(data)).read
  end

  def self.read_from(file_path)
    jsonld = JSON.parse(File.read(file_path))
    jsonld.dig('results', 'bindings')
  end

  def each
    if ENV['NO_DATA']
      []
    else
      super(self.class.fetch("#{@settings.flow_key}/#{@settings.key}"))
    end
  end

  def map_updated_at(feat)
    feat['lastUpdate']
  end

  def map_destination_id(_feat)
    @settings.destination_id
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
    feat['dc:identifier']
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
      ?publisher_name (GROUP_CONCAT(DISTINCT ?phone; SEPARATOR=",") AS ?contact_phone)
      (GROUP_CONCAT(DISTINCT ?email; SEPARATOR=",") AS ?contact_email) ?wheelchair ?image ?contact_website ?description
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
  GROUP BY ?identifier ?type ?label ?email ?full_name ?Latitude ?Longitude
          ?street_address ?postalcode_address ?city_address ?updated_at
          ?publisher_name ?wheelchair ?image ?contact_website ?description
SPARQL
