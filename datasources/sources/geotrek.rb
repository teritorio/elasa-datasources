# frozen_string_literal: true
# typed: false

require 'json'
require 'http'
require 'active_support/all'
require 'sorbet-runtime'
require_relative 'source'


class GeotrekSource < Source
  extend T::Sig

  class Settings < Source::SourceSettings
    const :base_url, String, name: 'url'
    const :website_details_url, String
    const :portal_id, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

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

  def fetch_practices
    rs = fetch_json_pages("#{@settings.base_url}/trek_practice/")
    rs.each{ |r| r['name'].compact_blank! }.index_by{ |r| r['id'] }
  end

  def fetch_difficulties
    rs = fetch_json_pages("#{@settings.base_url}/trek_difficulty/")
    rs.each{ |r| r['label'].compact_blank! }.index_by{ |r| r['id'] }
  end

  def fetch_trek_pois(trek_id)
    rs = fetch_json_pages("#{@settings.base_url}/poi/?near_trek=#{trek_id}&fields=id")
    rs.pluck('id').compact_blank
  end

  def fetch_pois(ids)
    fetch_json_pages("#{@settings.base_url}/poi/?ids=#{ids.join(',')}")
  end

  def fetch
    fetch_json_pages("#{@settings.base_url}/trek/?omit=geometry")
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
    @difficulties = fetch_difficulties
    @practices = fetch_practices
    treks = fetch
    treks.each{ |trek|
      trek['poi_ids'] = fetch_trek_pois(trek['id'])
    }
    poi_ids_all = treks.pluck('poi_ids').flatten.uniq
    pois = fetch_pois(poi_ids_all)
    super(ENV['NO_DATA'] ? [] : (treks.collect{ |trek| [:trek, trek] } + pois.collect{ |poi| [:poi, poi] }))
  end

  def practice_slug(practice)
    practice = @practices[practice]
    HashExcep[{
      'cycling' => 'bicycle',
      'horse' => 'horse',
      'mountain-bike' => 'mtb',
      'pedestre' => 'hiking',
    }][(practice&.dig('name', 'en') || practice&.dig('name', 'fr'))&.parameterize]
  end

  sig { returns(T::Array[MetadataRow]) }
  def metadatas
    super + @practices.collect{ |practice_id, practice|
      MetadataRow.new({
        data: {
          practice_slug(practice_id) => Metadata.from_hash({
            'name' => practice['name'],
            'attribution' => @settings.attribution,
          })
        }.compact_blank
      })
    } + [
      MetadataRow.new({
        data: {
          'geotrek-poi' => Metadata.from_hash({
            'name' => { 'en' => 'POI' },
            'attribution' => @settings.attribution,
          })
        }
      })
    ]
  end

  def map_destination_id(type_feat)
    type, feat = type_feat
    if type == :trek
      practice_slug(feat['practice'])
    else
      'geotrek-poi'
    end
  end

  def select(type_feat)
    type, feat = type_feat
    type != :trek || feat['portal'].include?(@settings.portal_id) && feat['practice'] && feat['published']['fr']
  end

  def map_id(type_feat)
    _, feat = type_feat
    feat['id']
  end

  def map_updated_at(type_feat)
    _, feat = type_feat
    feat['update_datetime']
  end

  def map_geometry(type_feat)
    type, feat = type_feat
    if type == :trek
      {
        type: 'Point',
        coordinates: feat['departure_geom'],
      }
    else
      feat['geometry']
    end
  end

  @@diacritics = [*0x1DC0..0x1DFF, *0x0300..0x036F, *0xFE20..0xFE2F].pack('U*')

  def slug(str)
    # How to make the slug from the name
    # https://github.com/GeotrekCE/Geotrek-rando-v3/issues/59#issuecomment-1086055798
    # https://github.com/GeotrekCE/Geotrek-rando-v3/blob/main/frontend/src/components/pages/search/utils.ts#L99
    str.unicode_normalize(:nfd).tr(@@diacritics, '').unicode_normalize(:nfc).tr('°«»/\'"’><®,', '').downcase.gsub(/[^a-z0-9\\-_]+/, '-').gsub(/^-/, '').gsub(/-$/, '')
  end

  def image(attachments)
    attachments&.filter{ |a|
      a['type'] == 'image'
    }&.pluck('url')&.compact_blank
  end

  def map_trek_tags(feat)
    r = feat
    name = r['name']&.compact_blank
    practice_name = @practices[r['practice']]&.dig('name')
    website_details = practice_name && name.collect{ |lang, _n|
      practice_name[lang] && name[lang] && [
        lang,
        @settings.website_details_url.gsub(
          '{{practice}}',
          slug(practice_name[lang])
        ).gsub(
          '{{name}}',
          slug(name[lang])
        )
      ] || nil
    }.compact.to_h || nil

    practice = practice_slug(r['practice'])
    {
      name: name,
      description: r['description_teaser'].compact_blank,
      'website:details': website_details,
      route: {
        "#{practice}": {
          difficulty: difficulty(@difficulties, r['difficulty']),
          duration: (r['duration'].to_f * 60).to_i,
          length: r['length_2d'].to_f / 1000,
        }.compact_blank,
        gpx_trace: r['gpx'],
        pdf: r['pdf']&.compact_blank,
      }.compact_blank,
      image: image(r['attachments']),
    }
  end

  def map_poi_tags(feat)
    r = feat
    {
      name: r['name']&.compact_blank,
      description: r['description'].compact_blank,
      website: [r['url']].compact_blank,
      image: image(r['attachments']),
    }
  end

  def map_tags(type_feat)
    type, feat = type_feat
    type == :trek ? map_trek_tags(feat) : map_poi_tags(feat)
  end

  def map_refs(type_feat)
    type, feat = type_feat
    type == :trek ? feat['poi_ids'] : nil
  end
end
