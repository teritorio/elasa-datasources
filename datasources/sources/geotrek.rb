# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'
require 'sorbet-runtime'
require_relative 'source'


class GeotrekSource < Source
  def initialize(job_id, destination_id, settings)
    super(job_id, destination_id, settings)
    @base_url = @settings['url']
    @website_details_url = @settings['website_details_url']
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
    @difficulties = fetch_difficulties(@base_url)
    @practices = fetch_practices(@base_url)
    super(fetch(@base_url))
  end

  def practice_slug(feat)
    practice = @practices[feat['practice']]
    HashExcep[{
      'cycling' => 'bicycle',
      'horse' => 'horse',
      'mountain-bike' => 'mtb',
      'pedestre' => 'hiking',
    }][(practice&.dig('name', 'en') || practice&.dig('name', 'fr'))&.parameterize]
  end

  def map_destination_id(feat)
    practice_slug(feat)
  end

  def select(feat)
    feat['portal'].include?(@settings['portal_id']) && feat['practice'] && feat['published']['fr']
  end

  def map_id(feat)
    feat['id']
  end

  def map_updated_at(feat)
    feat['update_datetime']
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: feat['departure_geom'],
    }
  end

  @@diacritics = [*0x1DC0..0x1DFF, *0x0300..0x036F, *0xFE20..0xFE2F].pack('U*')

  def slug(str)
    # How to make the slug from the name
    # https://github.com/GeotrekCE/Geotrek-rando-v3/issues/59#issuecomment-1086055798
    # https://github.com/GeotrekCE/Geotrek-rando-v3/blob/main/frontend/src/components/pages/search/utils.ts#L99
    str.unicode_normalize(:nfd).tr(@@diacritics, '').unicode_normalize(:nfc).tr('°«»/\'"’><®,', '').downcase.gsub(/[^a-z0-9\\-_]+/, '-').gsub(/^-/, '').gsub(/-$/, '')
  end

  def map_tags(feat)
    r = feat
    name = r['name']&.compact_blank
    practice_name = @practices[r['practice']]&.dig('name')
    website_details = practice_name && name.collect{ |lang, _n|
      practice_name[lang] && name[lang] && [
        lang,
        @website_details_url.gsub(
          '{{practice}}',
          slug(practice_name[lang])
        ).gsub(
          '{{name}}',
          slug(name[lang])
        )
      ] || nil
    }.compact.to_h || nil

    practice = practice_slug(r)
    {
      name: name,
      description: r['description_teaser'].reject { |_, v| v == '' },
      'website:details': website_details,
      route: {
        "#{practice}": {
          difficulty: difficulty(@difficulties, r['difficulty']),
          duration: (r['duration'].to_f * 60).to_i,
          length: r['length_2d'].to_f / 1000,
        },
        gpx_trace: r['gpx'],
        pdf: r['pdf']&.compact_blank,
      }.compact_blank,
      image: r['attachments']&.filter{ |a|
        a['type'] == 'image'
      }&.pluck('url')&.compact_blank,
    }
  end
end
