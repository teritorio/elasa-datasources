# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'
require 'sorbet-runtime'


# module Geotrek
class Geotrek
  def process(base_url, url_web, attribution)
    difficulties = fetch_difficulties(base_url)
    practices = fetch_practices(base_url)
    raw_json_treks = fetch(base_url)
    objects = map(raw_json_treks, practices, difficulties, attribution, url_web)
    { geotrek: objects }
  end

  def fetch_json_pages(url)
    next_url = url
    results = T.let([], T::Array[T.untyped])
    while next_url
      puts "Fetch... #{next_url}"
      resp = HTTP.follow.get(next_url)
      if !resp.status.success?
        raise [url, resp].inspect
      end

      json = JSON.parse(resp.body)
      next_url = json['next']
      results += json['results']
    end
    results
  end

  def fetch_practices(base_url)
    rs = fetch_json_pages("#{base_url}/trek_practice/")
    rs.each{ |r| r['name'].compact_blank! }.index_by{ |r| r['id'] }
  end

  def fetch_difficulties(base_url)
    rs = fetch_json_pages("#{base_url}/trek_difficulty/")
    rs.each{ |r| r['label'].compact_blank! }.index_by{ |r| r['id'] }
  end

  def fetch(base_url)
    fetch_json_pages("#{base_url}/trek/?omit=geometry")
  end

  def map(raw_json_treks, practices, difficulties, attribution, url_web)
    raw_json_treks.map{ |r|
      name = r['name']&.compact_blank
      practice = practices[r['practice']] && practices[r['practice']]['name'] || nil
      website = practice && name.collect{ |lang, _n|
        practice[lang] && name[lang] && [lang, "#{url_web}/#{practice[lang].parameterize}/#{name[lang].parameterize}/"] || nil
      }.compact.to_h || nil
      {
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: r['departure_geom'],
        },
        properties: {
          id: r['id'],
          timestamp: r['update_datetime'],
          tags: {
            source: attribution,
            name: name,
            descriptsion: r['description_teaser'].reject { |_, v| v == '' },
            website: website,
            practice: practice,
            difficulty: r['difficulty'] && difficulties[r['difficulty']] && difficulties[r['difficulty']]['label'] || nil,
            duration: (r['duration'].to_f * 60).to_i,
            gpx: r['gpx'],
            image: r['attachments']&.filter{ |a|
              a['filetype'] && a['filetype']['type'] == 'Photographie'
            }&.pluck('thumbnail')&.compact_blank,
          }.compact_blank
        }.compact_blank
      }
    }
  end
end
# end
