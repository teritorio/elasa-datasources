# frozen_string_literal: true
# typed: false

require 'nokogiri'
require 'open-uri'
require 'sorbet-runtime'
require_relative 'datasource'


# module Datasources
class TourismSystemXml < Datasource
  def process(_source_id, _settings, _dir)
    url, attribution =

    raw = fetch(url)
    objects = map(raw, attribution)
    objects = objects.collect{ |o|
      o[:_classification].collect{ |c|
        h = Hash(o)
        h[:_classification] = c
        h
      }
    }.flatten(1)
    objects.group_by{ |o|
      o[:_classification]
    }.transform_values{ |os|
      os.collect{ |o|
        o.except(:_classification)
      }
    }
  end

  def fetch(url)
    file = url.starts_with?('file://') ? File.open(url.gsub('file://', ''), 'r') : URI.parse(url).open
    xml = Nokogiri::XML(file.read)
    xml.remove_namespaces!
    xml
  end

  def map(raw, attribution)
    raw.xpath('/fiches/OI').collect{ |f|
      {
        _classification: f.xpath('DublinCore/Classification').collect(&:text),
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [
            f.xpath('Geolocalisations//Longitude')&.first&.text.to_f,
            f.xpath('Geolocalisations//Latitude')&.first&.text.to_f,
          ],
        },
        properties: {
          id: f.xpath('DublinCore/identifier').text,
          updated_at: f.xpath('DublinCore/modified').text,
          source: attribution,
          tags: {
            name: f.xpath('DublinCore/title').text,
            description: f.xpath('DublinCore/description').to_h{ |d| [d['lang'], d.text] },
            image: f.xpath('Multimedia/DetailMultimedia[@libelle="Image"]/URL').collect(&:text),
            # contact
            'addr:street': [
              f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//Adr1').text,
              f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//Adr2').text,
              f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//Adr3').text,
            ].compact_blank.join(', '),
            'addr:postcode': f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//CodePostal').text,
            'addr:city': [
              f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//Commune').text,
              f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//BureauDistrib').text,
              f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//Cedex').text,
            ].compact_blank.join(', '),
            'addr:country': [
              f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//ProvinceEtat').text,
              f.xpath('Contacts/DetailContact[@libelle="Etab/Lieu/Structure"]//Pays').text,
            ].compact_blank.join(', '),
          }.compact_blank,
        }.compact_blank,
      }
    }
  end
end
# end
