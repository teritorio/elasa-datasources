# frozen_string_literal: true
# typed: true

require_relative 'csv'

require 'sorbet-runtime'

require_relative 'source'


class InseeBpeSource < CsvSource
  class Settings < CsvSource::Settings
    const :code_labels, T::Hash[String, T::Hash[String, String]]
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  def metadatas
    super + @settings.code_labels.collect{ |code, name|
      MetadataRow.new({
        data: {
          "#{code[0]}-#{code[0..1]}-#{code}" => Metadata.from_hash({
            'name' => name,
            'attribution' => @settings.metadata.attribution,
          })
        }.compact_blank
      })
    }
  end

  def map_destination_id(feat)
    "#{feat['TYPEQU'][0]}-#{feat['TYPEQU'][0..1]}-#{feat['TYPEQU']}"
  end

  def select?(feat)
    super && @settings.code_labels.include?(feat['TYPEQU'])
  end

  def map_tags(feat)
    r = feat.to_h.transform_values{ |v| v == '_Z' ? nil : v }

    {
      name: { 'fr-FR' => r['NOMRS'] }.compact_blank,
      official_name: { 'fr-FR' => r['CNOMRS'] }.compact_blank,
      addr: {
        street: [r['NUMVOIE'], r['TYPVOIE'], r['LIBVOIE']].compact_blank.join(' '),
        postcode: r['CODPOS'],
        city: r['LIBCOM'],
      }.compact_blank,
      'ref:FR:SIRET' => r['SIRET'],
    }
  end

  def map_native_properties(feat, _properties)
    feat = feat.to_h.transform_values{ |v| v == '_Z' ? nil : v }

    feat
      .except(@settings.id, @settings.lon, @settings.lat, @settings.timestamp)
      .except('STATUT_DIFFUSION', 'LAMBERT_X', 'LAMBERT_Y', 'EPSG')
      .except('DEPCOM', 'DEP', 'REG', 'EPCI')
      .except('DCIRIS', 'QUALI_IRIS', 'IRISEE')
      .except('DOM', 'SDOM', 'TYPEQU')
      .except('CNOMRS', 'NOMRS', 'NUMVOIE', 'TYPVOIE', 'LIBVOIE', 'CODPOS', 'LIBCOM', 'SIRET')
  end
end
