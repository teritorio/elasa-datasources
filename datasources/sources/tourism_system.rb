# frozen_string_literal: true
# typed: false

require 'jsonpath'
require 'open-uri'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


def jp(object, path)
  JsonPath.on(object, "$.#{path}")
end

class TourismSystemSource < Source
  def initialize(source_id, attribution, settings, path)
    super(source_id, attribution, settings, path)
    @basic_auth = settings[:basic_auth]
    @id = settings[:id]
    @playlist_id = settings[:playlist_id]
    @thesaurus = settings[:thesaurus]
    @website_details_url = settings[:website_details_url]
  end

  def self.fetch(basic_auth, path)
    url = "https://#{basic_auth}@api.tourism-system.com#{path}"
    uri = URI.parse(url)

    uri_options = {}
    if !uri.userinfo.nil?
      uri_options[:http_basic_authentication] = [CGI.unescape(uri.user), CGI.unescape(uri.password)]
      uri.user = nil
      uri.password = nil
    end
    file = OpenURI.open_uri(uri, uri_options)

    JSON.parse(file.read)
  end

  def self.fetch_data(basic_auth, path)
    results = T.let([], T::Array[T.untyped])
    start = 0
    size = 1000

    data = []
    # Deals with stange remote paging API
    while start == 0 || data.size >= size - 1
      next_path = path + "?start=#{start}&size=#{size}"
      data = fetch(basic_auth, next_path)['data']
      results += data
      start += size
    end
    results
  end

  def https(url)
    url.gsub(%r{^http://}, 'https://')
  end

  def stars(code)
    {
      # Hotels
      '06.04.01.03.01' => '1',
      '06.04.01.03.02' => '2',
      '06.04.01.03.03' => '3',
      '06.04.01.03.04' => '4',
      '06.04.01.03.05' => '4S',
      '99.06.04.01.03.01' => '5',
    }[code]
  end

  def each
    raw = self.class.fetch_data(@basic_auth, "/content/ts/#{@id}/#{@playlist_id}")
    puts "#{self.class.name}: #{raw.size}"

    raw.each{ |f|
      id = f.dig('data', 'dublinCore', 'externalReference')
      website_details = @website_details_url.gsub('#{id}', id)

      yield ({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [
            jp(f, '.geolocations..longitude').first.to_f,
            jp(f, '.geolocations..latitude').first.to_f,
          ],
        },
        properties: {
          id: id,
          updated_at: f.dig('data', 'dublinCore', 'modified'),
          source: @attribution,
          tags: {
            name: f.dig('metadata', 'name'),
            description: f.dig('data', 'dublinCore', 'description'),
            phone: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.01")]')&.pluck('particular')&.compact_blank,
            email: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.04")]')&.pluck('particular')&.compact_blank,
            website: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="04.02.05")]')&.pluck('particular')&.compact_blank,
            'website:details': website_details,
            facebook: jp(f, '.contacts[*][?(@.type=="04.03.13")]..communicationMeans[*][?(@.type=="99.04.02.01")]')&.pluck('particular')&.compact_blank,
            image: jp(f, '.multimedia[*][?(@.type=="03.01.01")].URL').map{ |u| https(u) }, # 03.01.01 = Image
            addr: {
                street: [ # 04.03.13 = Etab/Lieu/Structure
                jp(f, '.contacts[*][?(@.type=="04.03.13")]..address1'),
                jp(f, '.contacts[*][?(@.type=="04.03.13")]..address2'),
                jp(f, '.contacts[*][?(@.type=="04.03.13")]..address3'),
              ].compact_blank.join(', '),
                postcode: jp(f, '.contacts[*][?(@.type=="04.03.13")]..zipCode').first,
                city: [
                jp(f, '.contacts[*][?(@.type=="04.03.13")]..commune'),
                # jp(f, '.contacts[*][?(@.type=="04.03.13")]..bureauDistrib'), # FIXME, not sure about property name
                # jp(f, '.contacts[*][?(@.type=="04.03.13")]..cedex'), # FIXME, not sure about property name
              ].compact_blank.join(', '),
                country: [
                # jp(f, '.contacts[*][?(@.type=="04.03.13")]..state'), # FIXME, not sure about property name
                jp(f, '.contacts[*][?(@.type=="04.03.13")]..country'),
              ].compact_blank.join(', '),
            },
            cuisine: (
              f.dig('data', 'dublinCore', 'criteria')&.pluck('criterion')&.select{ |v|
                v.start_with?('02.01.13.03.') || v.include?('.00.02.01.13.03.')
              }&.map{ |v|
                @thesaurus[v] || v
              }),
            stars: stars(jp(f, '.ratings.officials..ratingLevel').select{ |s| s.include?('06.04.01.03.') }.first),
          }.compact_blank,
        }.compact_blank,
      })
    }
  end
end
