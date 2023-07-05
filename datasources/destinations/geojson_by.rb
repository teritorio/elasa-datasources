# frozen_string_literal: true
# typed: true

require 'json'
require_relative 'geojson'

class GeoJsonBy < Destination
  attr_reader :output_file

  def initialize(path)
    super(path)
    @destinations = Hash.new { |h, k| h[k] = GeoJson.new(path, k) }
  end

  def write(row)
    raise 'Missing destination_id field' if !row[:destination_id]

    @destinations[row[:destination_id]].write(row.except(:destination_id))
  end

  def close
    @destinations.each_value(&:close)
  end
end
