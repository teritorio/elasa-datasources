# frozen_string_literal: true
# typed: false

require 'jsonpath'
require 'open-uri'
require 'cgi'
require 'sorbet-runtime'


def jp(object, path)
  JsonPath.on(object, "$.#{path}")
end

# module TourismSystem
class TourismSystem
  def process(url, attribution)
    fetch(url).collect { |playlist|
      [playlist['metadata']['name'], playlist['metadata']['id']]
    }.select{ |name, _id|
      name.include?('Teritorio')
    }.to_h.transform_values{ |id|
      raw = fetch("#{url}/#{id}")
      map(raw, attribution)
    }
  end

  def fetch(url)
    uri = url.starts_with?('file://') ? File.open(url.gsub('file://', ''), 'r') : URI.parse(url)

    uri_options = {}
    if !uri.userinfo.nil?
      uri_options[:http_basic_authentication] = [CGI.unescape(uri.user), CGI.unescape(uri.password)]
      uri.user = nil
      uri.password = nil
    end
    file = OpenURI.open_uri(uri, uri_options)

    JSON.parse(file.read)['data']
  end

  def https(url)
    url.gsub(%r{^http://}, 'https://')
  end

  def map(raw, attribution)
    raw.collect{ |f|
      # puts f.inspect
      {
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [
            jp(f, '.geolocations..longitude').first.to_f,
            jp(f, '.geolocations..latitude').first.to_f,
          ],
        },
        properties: {
          id: f.dig('metadata', 'id'),
          timestamp: f.dig('data', 'dublinCore', 'modified'),
          tags: {
            source: attribution,
            name: f.dig('metadata', 'name'),
            description: f.dig('data', 'dublinCore', 'description'),
            image: jp(f, '.multimedia[*][?(@.type=="03.01.01")].URL').map{ |u| https(u) }, # 03.01.01 = Image
            # contact
            'addr:street': [ # 04.03.13 = Etab/Lieu/Structure
              jp(f, '.contacts[*][?(@.type=="04.03.13")]..address1'),
              jp(f, '.contacts[*][?(@.type=="04.03.13")]..address2'),
              jp(f, '.contacts[*][?(@.type=="04.03.13")]..address3'),
            ].compact_blank.join(', '),
            'addr:postcode': jp(f, '.contacts[*][?(@.type=="04.03.13")]..zipCode').first,
            'addr:city': [
              jp(f, '.contacts[*][?(@.type=="04.03.13")]..commune'),
              # jp(f, '.contacts[*][?(@.type=="04.03.13")]..bureauDistrib'), # FIXME, not sure about property name
              # jp(f, '.contacts[*][?(@.type=="04.03.13")]..cedex'), # FIXME, not sure about property name
            ].compact_blank.join(', '),
            'addr:country': [
              # jp(f, '.contacts[*][?(@.type=="04.03.13")]..state'), # FIXME, not sure about property name
              jp(f, '.contacts[*][?(@.type=="04.03.13")]..country'),
            ].compact_blank.join(', '),
          }.compact_blank,
        }.compact_blank,
      }
    }
  end
end
# end
