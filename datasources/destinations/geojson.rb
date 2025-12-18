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

    destination = destination_path_base(destination_id)
    File.write("#{destination}geojson", JSON.pretty_generate(fc))
  end
end
