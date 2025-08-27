# frozen_string_literal: true
# typed: true

require_relative 'transformer'
require 'rgeo/geo_json'


class GeomUnionTransformer < Transformer
  extend T::Generic

  class Settings < Transformer::TransformerSettings
    const :group_by, T.nilable(T::Array[String])
  end

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super

    @rows = Hash.new { |h, k| h[k] = [] }
  end

  sig { override.params(row: Row).returns(T.untyped) }
  def process_data(row)
    @rows[row[:destination_id]] << row
    nil
  end

  def properties_intersection(properties_a, properties_b)
    a = properties_a
    b = properties_b
    {
      id: [a[:id], b[:id]].min,
      tags: (a[:tags].to_a & b[:tags].to_a).to_h,
      natives: (a[:natives].to_a & b[:natives].to_a).to_h,
      updated_at: [a[:updated_at], b[:updated_at]].max,
      source: a[:source] || b[:source],
    }.compact_blank
  end

  def close_data
    @rows.each{ |destination_id, rows|
      rows_groups = (
        if @settings.group_by.nil?
          { destination_id => rows }
        else
          rows.group_by{ |row|
            T.must(@settings.group_by).collect{ |k|
              row[:properties].dig(k[0]&.to_sym, k[1]&.to_sym, *k[2..])
            }
          }
        end
      )

      rows_groups.each_value{ |rows_group|
        geoms = rows_group.pluck(:geometry)
        geom_collection = RGeo::GeoJSON.decode({ type: 'GeometryCollection', geometries: geoms }.to_json)
        next if geom_collection.nil?

        geom_merged = RGeo::GeoJSON.encode(geom_collection.unary_union)
        properites = rows_group.pluck(:properties).reduce { |sum, row| properties_intersection(sum, row) }
        yield ({
          destination_id: destination_id,
          type: 'Feature',
          properties: properites,
          geometry: geom_merged,
        })
      }
    }

    nil
  end
end
