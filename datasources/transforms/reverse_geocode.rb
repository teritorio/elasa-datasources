# frozen_string_literal: true
# typed: true

require 'http'
require 'csv'
require 'rgeo'
require 'rgeo-geojson'

require_relative 'transformer'


class ReverseGeocode < Transformer
  extend T::Generic
  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super(settings)
    @rows = []
  end

  def process_data(row)
    @rows << row
    nil
  end

  def split_by_addr(features)
    groups = features.group_by{ |f|
      !f[:properties][:tags].key?(:addr) ||
        !f[:properties][:tags][:addr].key?('postcode') ||
        !f[:properties][:tags][:addr].key?('city')
    }
    [
      groups[false] || [],
      groups[true] || []
    ]
  end

  def reverse(features, &block)
    coord_features = features.group_by{ |f|
      geom = RGeo::GeoJSON.decode(f[:geometry].transform_keys(&:to_s))
      point = geom.respond_to?(:point_on_surface) ? geom.point_on_surface : geom
      [point.x, point.y] if geom
    }.to_a
    reverse_query(coord_features.collect(&:first)).zip(coord_features.collect(&:last)).each { |addr, fs|
      fs.each{ |f|
        if addr['result_city']
          if f[:properties][:tags].key?(:addr)
            f[:properties][:tags].deep_merge_array({
              addr: {
                postcode: addr['result_postcode'],
                city: addr['result_city'],
              },
              source: {
                'addr:postcode' => 'BAN - ETALAB-2.0',
                'addr:city' => 'BAN - ETALAB-2.0',
              },
            })
          else
            f[:properties][:tags][:addr] =
              f[:properties][:tags].deep_merge_array({
                addr: {
                  street: addr['result_name'],
                  postcode: addr['result_postcode'],
                  city: addr['result_city'],
                },
                source: {
                  'addr' => 'BAN - ETALAB-2.0',
                },
              })
          end
        end

        block.call(f)
      }
    }
  end

  def close_data(&block)
    with_addr, without_addr = split_by_addr(@rows)
    with_addr.each(&block)
    reverse(without_addr, &block)
  end

  def reverse_query(lon_lats)
    csv_data = CSV.generate { |csv|
      csv << %w[lon lat]
      lon_lats.each{ |ll| csv << ll }
    }
    resp = HTTP.post('https://api-adresse.data.gouv.fr/reverse/csv/', form: {
      delimiter: ',',
      encoding: 'utf-8',
      data: HTTP::FormData::Part.new(csv_data, content_type: 'text/csv', filename: 'yes_i_am_csv.csv')
    })

    if !resp.status.success?
      raise "Fails reverse geocoding #{resp.body}"
    end

    CSV.parse(resp.body.to_s, col_sep: ',', headers: true)
  end
end
