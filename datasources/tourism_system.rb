# frozen_string_literal: true
# typed: false

require 'jsonpath'
require 'open-uri'
require 'cgi'
require 'sorbet-runtime'
require_relative 'datasource'


def jp(object, path)
  JsonPath.on(object, "$.#{path}")
end

# module Datasources
class TourismSystem < Datasource
  def process(_source_id, settings, _dir)
    id = settings['id']
    basic_auth = settings['basic_auth']
    attribution = settings['attribution']

    thesaurus_fr = fetch("https://#{basic_auth}@api.tourism-system.com/thesaurus/ts/#{id}/tree/fr")
    thesaurus = parse_thesaurus(thesaurus_fr).to_h

    url = "https://#{basic_auth}@api.tourism-system.com/content/ts/#{id}"
    fetch_data(url).collect { |playlist|
      [playlist['metadata']['name'], playlist['metadata']['id']]
    }.select{ |name, _id|
      name.include?('Teritorio')
    }.to_h.transform_values{ |id|
      raw = fetch_data("#{url}/#{id}")
      map(raw, attribution, thesaurus)
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

    JSON.parse(file.read)
  end

  def fetch_data(url)
    results = T.let([], T::Array[T.untyped])
    start = 0
    size = 1000

    data = []
    while start == 0 || data.size == size - 1
      next_url = url + "?start=#{start}&size=#{size}"
      puts "Fetch... #{next_url}"
      data = fetch(next_url)['data']
      results += data
      start += size
    end
    results
  end

  def parse_thesaurus(thesaurus)
    thesaurus.collect{ |sub|
      [[sub['key'], sub['label']]] + (
         sub.key?('children') ? parse_thesaurus(sub['children']) : []
       )
    }.flatten(1)
  end

  def https(url)
    url.gsub(%r{^http://}, 'https://')
  end

  def stars(s)
    {
      # Hotels
      '06.04.01.03.01' => '1',
      '06.04.01.03.02' => '2',
      '06.04.01.03.03' => '3',
      '06.04.01.03.04' => '4',
      '06.04.01.03.05' => '4S',
      '99.06.04.01.03.01' => '5',
    }[s]
  end

  def map(raw, attribution, thesaurus)
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
          source: attribution,
          tags: {
            name: f.dig('metadata', 'name'),
            description: f.dig('data', 'dublinCore', 'description'),
            phone: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.01")]')&.pluck('particular')&.compact_blank,
            email: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.04")]')&.pluck('particular')&.compact_blank,
            website: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.05")]')&.pluck('particular')&.compact_blank,
            facebook: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="99.04.02.01")]')&.pluck('particular')&.compact_blank,
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
            cuisine: (
              f.dig('data', 'dublinCore', 'criteria')&.pluck('criterion')&.select{ |v|
                v.start_with?('02.01.13.03.') || v.include?('.00.02.01.13.03.')
              }&.map{ |v|
                thesaurus[v] || v
              }),
            stars: stars(jp(f, '.ratings.officials..ratingLevel').select{ |s| s.include?('06.04.01.03.') }.first),
          }.compact_blank,
        }.compact_blank,
      }
    }
  end
end
# end
