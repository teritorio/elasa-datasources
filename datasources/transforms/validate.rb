# frozen_string_literal: true
# typed: true

require 'json'
require 'json-schema'

require_relative 'transformer'


class ValidateTransformer < Transformer
  def initialize(settings)
    super(settings)

    @count = 0
    @bad = {
      missing_geometry: 0,
      null_island_geometry: 0,
      pass: 0,
    }

    # Schema from https://geojson.org/schema/Feature.json
    @geojson_schema = JSON.parse(File.new('datasources/transforms/validate-geojson-feature.schema.json').read)
    @properties_schema = JSON.parse(File.new('datasources/transforms/validate-properties.schema.json').read)
  end

  def process_data(row)
    @count += 1

    if row[:geometry].blank?
      @bad[:missing_geometry] += 1
      return
    end

    if row[:geometry][:type] == 'Point' && row[:geometry][:coordinates] == [0.0, 0.0]
      @bad[:null_island_geometry] += 1
      return
    end

    begin
      JSON::Validator.validate!(@geojson_schema, row)
      JSON::Validator.validate!(@properties_schema, row[:properties])
    rescue StandardError => e
      puts row.inspect
      raise e
    end

    @bad[:pass] += 1
    row
  end

  def close_data
    bad = @bad.select{ |_k, v| v != 0 }.to_h.compact_blank
    return unless !bad.empty? && bad[:pass] != @count

    puts "      ! #{bad.inspect}"
  end
end
