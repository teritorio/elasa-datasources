# frozen_string_literal: true
# typed: true

require 'json'

class GeoJson
  attr_reader :output_file

  def initialize(destination_id, path)
    @destination_id = destination_id
    @path = path
    @rows = []
  end

  def write(row)
    @rows << row
  end

  def close
    puts "#{self.class.name}: #{@destination_id} #{@rows.size}"

    fc = {
      type: 'FeatureCollection',
      features: @rows,
    }
    File.write("#{@path}/#{@destination_id.gsub('/', '_')}.geojson", JSON.pretty_generate(fc))
  end
end
