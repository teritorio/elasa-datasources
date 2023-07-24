# frozen_string_literal: true
# typed: true

require 'json'
require 'json-schema'

require_relative 'transformer'


class ValidateTransformer < Transformer
  def initialize(settings)
    super(settings)
    @additional_tags = settings['additional_tags'] || false

    @i18n = {}

    @count = 0
    @bad = {
      missing_geometry: 0,
      null_island_geometry: 0,
      pass: 0,
    }

    @i18n_schema = JSON.parse(File.new('datasources/schemas/i18n.schema.json').read)
    @i18n_schema['properties'] = { destination_id: { type: 'string' } }

    # Schema from https://geojson.org/schema/Feature.json
    @geojson_schema = JSON.parse(File.new('datasources/schemas/geojson-feature.schema.json').read)
  end

  def validate_schema_i18n_key(base, properties, i18n)
    keys = properties.keys.collect{ |key| Regexp.new((base + [Regexp.quote(key)]).join(':')) }
    keys_without_i18n = keys.select{ |key| !i18n.keys.find{ |i18n_key| key.match(i18n_key) } }
    raise "Tags Keys without i18n : #{keys_without_i18n.inspect}" if !keys_without_i18n.empty?

    # i18n_without_keys = i18n.keys.select{ |i18n_key| !keys.find{ |key| key.match(i18n_key) } }
    # raise "Tags Key pending in i18n : #{i18n_without_keys.inspect}" if !i18n_without_keys.empty?
  end

  def validate_schema_i18n_enum(base, properties, i18n)
    enums = properties.select{ |_key, value|
      value['type'] == 'array' && !value['items']['enum'].nil?
    }.collect{ |key, value|
      [key, value['items']['enum']]
    } + properties.select{ |_key, value|
      !value['enum'].nil?
    }.collect{ |key, value|
      [key, value['enum']]
    }

    enums.collect{ |key, enum|
      key_match = Regexp.new((base + [Regexp.quote(key)]).join(':'))
      i18n_key = i18n.keys.find{ |k| key_match.match(k) }
      i18n_missing_values = enum - (i18n[i18n_key]['values'] || {}).keys
      logger.debug("Tags Key values without i18n : #{key}=#{i18n_missing_values.join('|')}") if !i18n_missing_values.empty?

      i18n_pending_values = (i18n[i18n_key]['values'] || {}).keys - enum
      logger.debug("Tags Key values pending i18n : #{key}=#{i18n_pending_values.join('|')}") if !i18n_pending_values.empty?

      !i18n_missing_values.empty? || !i18n_pending_values.empty?
    }.find.first && raise('Tags value i18n Error')
  end

  def validate_schema_i18n_object(base, properties, i18n)
    properties.select{ |_key, value|
      value['type'] == 'object' && !value['properties'].nil?
    }.collect{ |key, value|
      validate_schema_i18n(base + [Regexp.quote(key)], value['properties'], i18n)
    }

    properties.select{ |_key, value|
      value['type'] == 'object' && value['additionalProperties'] && value['additionalProperties']['type'] == 'object'
    }.collect{ |key, value|
      validate_schema_i18n(base + [Regexp.quote(key), '[^:]+'], value['additionalProperties']['properties'], i18n)
    }
  end

  def validate_schema_i18n(base, properties, i18n)
    validate_schema_i18n_key(base, properties, i18n)
    validate_schema_i18n_enum(base, properties, i18n)
    validate_schema_i18n_object(base, properties, i18n)
  end

  def process_schema(schema)
    @properties_tags_schema = schema[:schema] || {}
    @properties_schema = JSON.parse(File.new('datasources/schemas/properties.schema.json').read)
    @properties_schema['properties']['tags'] = @properties_tags_schema
    @properties_schema['$defs'] = (@properties_schema['$defs'] || {}).merge(@properties_tags_schema['$defs'] || {})

    # Relax constraints on schema
    if @additional_tags
      @properties_schema['properties']['tags']['additionalProperties'] = additional_tags
      %w[shop amenity leisure tourism natural water highway].each{ |key|
        @properties_schema['properties']['tags']['properties'][key] = { type: 'string' }
      }
    end

    JSON::Validator.validate!(@i18n_schema, schema[:i18n])
    validate_schema_i18n([], @properties_tags_schema['properties'], schema[:i18n])
    @schema = schema[:schema]
    @i18n = schema[:i18n]
    schema
  end

  def validate_i18n(properties)
    missing = properties.collect{ |key, value|
      if @properties_tags_schema.key?(key.to_s) && @i18n.key?(key.to_s) && @i18n[key.to_s].key?(:values) && !@i18n[key.to_s][:values].key?(value.to_s)
        "#{key}=#{value}"
      end
    }.compact
    raise "Missing key or key=value: #{missing.join(', ')}" if missing.present?
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
      validate_i18n(row[:properties][:tags])
    rescue StandardError => e
      logger.call(row.inspect)
      raise e
    end

    @bad[:pass] += 1
    row
  end

  def close_data
    bad = @bad.select{ |_k, v| v != 0 }.to_h.compact_blank
    return unless !bad.empty? && bad[:pass] != @count

    logger.info("    ! #{bad.inspect}")

    # TODO: check for additionalProperties translation
  end
end
