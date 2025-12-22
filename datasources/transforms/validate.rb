# frozen_string_literal: true
# typed: true

require 'json'
require 'json-schema'

require_relative 'transformer'


class ValidateTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super

    @i18n = {}

    @count = 0
    @bad = {
      missing_geometry: 0,
      null_island_geometry: 0,
      pass: 0,
    }
    @missing_enum_value = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = 0 } }

    @metadata_schema = JSON.parse(File.new('../../datasources/schemas/metadata.schema.json').read)

    @i18n_schema = JSON.parse(File.new('../../datasources/schemas/i18n.schema.json').read)
    @i18n_schema['properties'] = { destination_id: { type: 'string' } }

    @i18n_osm_tags = JSON.parse(File.new('../../datasources/schemas/osm_tags.schema.json').read)

    # Schema from https://geojson.org/schema/Feature.json
    @geojson_schema = JSON.parse(File.new('../../datasources/schemas/geojson-feature.schema.json').read)
  end

  sig { params(metadata: Source::MetadataRow).returns(T.nilable(Source::MetadataRow)) }
  def process_metadata(metadata)
    m = metadata.data.transform_values{ |m| m.serialize.except('destination_internal').compact_blank }
    JSON::Validator.validate!(@metadata_schema, m.to_json)
    metadata
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
      key_regex = (base + [Regexp.quote(key)]).join(':')
      key_match = Regexp.new("^#{key_regex}$")
      i18n_key = i18n.keys.find{ |k| key_match.match(k) }
      i18n_missing_values = enum - (i18n[i18n_key]['values'] || {}).keys
      logger.debug("Tags Key values without i18n : #{key}=#{i18n_missing_values.join('|')}") if !i18n_missing_values.empty?

      i18n_pending_values = (i18n[i18n_key]['values'] || {}).keys - enum
      logger.debug("Tags Key values in i18n but not in schema : #{key}=#{i18n_pending_values.join('|')}") if !i18n_pending_values.empty?

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
      value['type'] == 'object' && ![true, false].include?(value['additionalProperties']) && value['additionalProperties']['type'] == 'object'
    }.collect{ |key, value|
      validate_schema_i18n(base + [Regexp.quote(key), '[^:]+'], value['additionalProperties']['properties'], i18n)
    }
  end

  def validate_schema_i18n(base, properties, i18n)
    validate_schema_i18n_key(base, properties, i18n)
    validate_schema_i18n_enum(base, properties, i18n)
    validate_schema_i18n_object(base, properties, i18n)
  end

  sig { params(schema: Source::SchemaRow).returns(T.nilable(Source::SchemaRow)) }
  def process_schema(schema)
    @properties_tags_schema = schema.tags_schema || { type: 'object', additionalProperties: false }
    @properties_natives_schema = schema.natives_schema || { type: 'object', additionalProperties: false }
    @properties_schema = JSON.parse(File.new('../../datasources/schemas/properties.schema.json').read)
    @properties_schema['properties']['tags'] = @properties_tags_schema
    @properties_schema['properties']['natives'] = @properties_natives_schema
    @properties_schema['$defs'] = (@properties_schema['$defs'] || {}).merge(@properties_tags_schema['$defs'] || {})

    JSON::Validator.validate!(@i18n_schema, schema.i18n)
    validate_schema_i18n([], @properties_tags_schema['properties'], schema.i18n) if !@properties_tags_schema['properties'].nil?
    validate_schema_i18n([], @properties_natives_schema['properties'], schema.i18n) if !@properties_natives_schema['properties'].nil?
    @tags_schema = schema.tags_schema
    @natives_schema = schema.natives_schema
    @i18n = schema.i18n
    schema
  end

  sig { params(data: Source::OsmTagsRow).returns(T.nilable(Source::OsmTagsRow)) }
  def process_osm_tags(data)
    JSON::Validator.validate!(@i18n_osm_tags, data.data.collect{ |t| t.serialize.compact_blank })
    data
  end

  def validate_i18n(properties, properties_schema)
    missing = properties.collect{ |key, value|
      if properties_schema.key?(key.to_s) && @i18n.key?(key.to_s) && @i18n[key.to_s].key?(:values) && !@i18n[key.to_s][:values].key?(value.to_s)
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
      JSON::Validator.validate!(@geojson_schema, row, errors_as_objects: true)

      errors = JSON::Validator.fully_validate(@properties_schema, row[:properties], errors_as_objects: true)
      errors.reverse.each{ |error| # Reverse to remove values of array from the end
        raise("#{error[:message]} in #{row[:properties].inspect}") unless error[:failed_attribute] == 'Enum'

        # Extract the faulty path
        path = error[:fragment][2..].split('/')
        path[0] = path[0].to_sym
        path[1] = path[1].to_sym if path[0] == :tags
        if Integer(path[-1].to_s, exception: false).nil?
          # Collected the faulty value
          @missing_enum_value[path[-1]][row[:properties].dig(*path)] += 1
          # Remove the attribute
          row[:properties].dig(*path[..-2]).delete(path[-1])
        else
          index = Integer(path.pop.to_s)

          # Collected the faulty value
          @missing_enum_value[path[-1]][row[:properties].dig(*path)[index]] += 1
          # Remove the attribute
          row[:properties].dig(*path).delete_at(index)
        end
      }

      validate_i18n(row[:properties][:tags], @properties_tags_schema) if !row[:properties][:tags].nil?
      validate_i18n(row[:properties][:natives], @properties_natives_schema) if !row[:properties][:natives].nil?
    rescue StandardError => e
      logger.debug(row.inspect)
      raise e
    end

    @bad[:pass] += 1
    row
  end

  def close_data
    bad = @bad.select{ |_k, v| v != 0 }.to_h.compact_blank
    if bad.empty? || bad[:pass] != @count
      logger.info("    ! #{bad.inspect}")
    end
    return if @missing_enum_value.empty?

    logger.info('    ! Missing values in schema for keys:')
    @missing_enum_value.transform_keys(&:to_s).transform_values{ |counts|
      counts.to_a.sort_by{ |count| count[0].to_s }.collect{ |k, v| "#{k} x#{v}" }
    }.to_a.sort_by(&:first).collect{ |k, counts| counts.collect{ |count| "#{k}=#{count}" } }.flatten.each{ |log|
      logger.info("    !     #{log}")
    }

    # TODO: check for additionalProperties translation
  end
end
