# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class CinorTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  def map_id(feat)
    feat['cinor_id_sig']
  end

  sig { params(properties: T::Hash[Symbol, T.untyped]).returns([T::Hash[Symbol, T.untyped], T::Hash[String, T.untyped]]) }
  def parse_cinor(properties)
    tags = {}
    cinor = {}
    properties.each { |key, value|
      if key.start_with?('tags.')
        keys = T.let(key[5..].split('.'), T::Array[String])
        first_key = T.must(keys[0]).to_sym
        others_keys = T.must(keys[1..]).reverse
        tags[first_key] = (
          if tags[first_key].is_a?(Hash)
            tags[first_key].merge(others_keys.inject(value) { |sum, k| { k => sum } })
          else
            others_keys.inject(value) { |sum, k| { k => sum } }
          end
        )
      elsif key.start_with?('cinor_')
        cinor[key[6..]] = value
      end
    }
    [tags, cinor]
  end

  sig { params(cinor: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def cinor_to_osm(cinor)
    {
      ref: {
        'FR:SIRET' => cinor['siret'],
      }.compact_blank,
      opening_hours: cinor['horaire_ouverture'],
      name: {
        'fr-FR' => cinor['enseigne'],
        # nom_commercial
      }.compact_blank,
      phone: [
        cinor['telephone_fixe'],
        cinor['telephone_mobile'],
        cinor['telephone_autre'],
      ].compact_blank,
      # fax
      email: [cinor['e_mail']].compact_blank,
      stars: cinor['classement']&.to_i.to_s,
      image: [cinor['url_image']].compact_blank,
      website: [cinor['site_web']].compact_blank,

      short_description: {
        'fr-FR' => cinor['accroche'],
      }.compact_blank,
      description: {
        'fr-FR' => cinor['descriptif'],
      }.compact_blank,
      addr: {
        'street' => [
          # Missing street field
          cinor['lieux_dit']
        ].compact.join,
        'postcode' => cinor['code_postal'].to_s,
        # bureau_postal
        'city' => cinor['nom_commune'],
      }.compact_blank
    }.compact_blank
  end

  sig { params(row: Row).returns(T.untyped) }
  def process_data(row)
    tags, cinor = parse_cinor(row[:properties].delete(:natives).compact_blank)
    cinor_tags = cinor_to_osm(cinor)

    # Priority 1. OSM, 2. Cinor
    cinor_tags.keys.to_a.each{ |k|
      if !tags.key?(k)
        cinor_tags[:"source:#{k}"] = '© CINOR'
      end
    }
    row[:properties][:tags] = cinor_tags.merge(tags)
    # Exception for image, keep all images, Cinor, first
    tags[:image] = ((cinor_tags[:image] || []) + (tags[:image] || []))
    # Exception for addr
    tags[:addr] = (cinor_tags[:addr] || {}).merge(tags[:addr] || {})
    tags = tags.compact_blank

    # "groupe_categorie" : "Hébergement"
    # "nom_categorie" : "Hôtel"
    # "nom_sous_categorie" : "Hôtel"

    row[:properties][:natives] = cinor.slice('en_ligne', 'zone', 'labels', 'recommandation_oti').compact_blank
    row
  end
end
