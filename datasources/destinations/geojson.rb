# frozen_string_literal: true
# typed: true

require 'json'
require_relative 'destination'

class GeoJson < Destination
  attr_reader :output_file

  def initialize(path)
    super(path)
    @destinations = Hash.new { |h, k|
      h[k] = []
    }
  end

  def write_data(row)
    @destinations[row[:destination_id]] << row.except(:destination_id)
  end

  def close
    @destinations.each{ |destination_id, rows|
      puts "    < #{self.class.name}: #{destination_id}: #{rows.size}"

      fc = {
        type: 'FeatureCollection',
        features: rows,
      }
      File.write("#{@path}/#{destination_id.gsub('/', '_')}.geojson", JSON.pretty_generate(fc))
    }
  end
end
