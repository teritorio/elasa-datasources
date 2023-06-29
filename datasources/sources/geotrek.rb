# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'
require 'sorbet-runtime'
require_relative 'source'


class GeotrekSource < Source
  def initialize(source_id, attribution, settings, path)
    super(source_id, attribution, settings, path)
    @base_url = settings['url']
    @website_details_url = settings['website_details_url']
  end

  def fetch_json_pages(url)
    next_url = url
    results = T.let([], T::Array[T.untyped])
    while next_url
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

  def difficulty(difficulties, difficulty)
    difficulty_level = difficulty && difficulties[difficulty] && difficulties[difficulty]['cirkwi_level'] || nil
    if difficulty_level.nil?
      nil
    elsif difficulty_level < 3
      'easy'
    elsif difficulty_level < 5
      'normal'
    else
      'hard'
    end
  end

  def each
    difficulties = fetch_difficulties(@base_url)
    practices = fetch_practices(@base_url)
    raw = fetch(@base_url)
    puts "#{self.class.name}: #{raw.size}"

    raw.select{ |r|
      r['practice']
    }.each{ |r|
      name = r['name']&.compact_blank
      practice = practices[r['practice']]
      practice_slug = HashExcep[{
        'cycling' => 'bicycle',
        'horse' => 'horse',
        'mountain-bike' => 'mtb',
        'pedestre' => 'hiking',
      }][(practice&.dig('name', 'en') || practice&.dig('name', 'fr'))&.parameterize]
      practice_name = practice&.dig('name')
      website_details = practice_name && name.collect{ |lang, _n|
        practice_name[lang] && name[lang] && [lang, @website_details_url.gsub('{{practice}}', practice_name[lang].parameterize).gsub('{{name}}', name[lang].parameterize)] || nil
      }.compact.to_h || nil

      yield ({
        destination_id: practice_slug,
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: r['departure_geom'],
        },
        properties: {
          id: r['id'],
          updated_at: r['update_datetime'],
          source: @attribution,
          tags: {
            name: name,
            description: r['description_teaser'].reject { |_, v| v == '' },
            'website:details': website_details,
            route: {
              "#{practice_slug}:difficulty": difficulty(difficulties, r['difficulty']),
              "#{practice_slug}:duration": (r['duration'].to_f * 60).to_i,
              "#{practice_slug}:length": r['length_2d'].to_f / 1000,
              gpx_trace: r['gpx'],
              pdf: r['pdf']&.compact_blank,
            }.compact_blank,
            image: r['attachments']&.filter{ |a|
              a['type'] == 'image'
            }&.pluck('url')&.compact_blank,
          }.compact_blank
        }.compact_blank
      })
    }
  end
end
