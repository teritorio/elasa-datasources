# frozen_string_literal: true
# typed: true

require 'json'
require_relative 'destination'

class GeoJson < Destination
  def close_data(destination_id, rows)
    fc = {
      type: 'FeatureCollection',
      features: rows,
    }
    File.write("#{@path}/#{destination_id.gsub('/', '_')}.geojson", JSON.pretty_generate(fc))
  end
end
