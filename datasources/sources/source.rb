# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

class HashExcep < Hash
  def [](key)
    raise "Missing key \"#{key}\" in Hash at #{caller_locations&.[](0)}" if !key?(key)

    super(key)
  end
end

class Source
  extend T::Sig
  extend T::Helpers
  abstract!

  class SourceSettings < T::InexactStruct
    const :attribution, T.nilable(String)
    const :allow_partial_source, T::Boolean, default: false
    const :native_properties, T.nilable(T::Hash[String, T.untyped])
  end

  extend T::Generic
  SettingsType = type_member{ { upper: SourceSettings } } # Generic param

  sig { params(job_id: T.nilable(String), destination_id: T.nilable(String), settings: SettingsType).void }
  def initialize(job_id, destination_id, settings)
    @job_id = job_id
    @destination_id = destination_id
    T.assert_type!(settings, SourceSettings) # FIXME: Manually assert type, because type is not asserted automatically, because of genereics ? (why?)
    @settings = settings
  end

  def schema
    {
      destination_id: @destination_id,
    }
  end

  def osm_tags
    {
      destination_id: @destination_id,
      data: [],
    }
  end

  def select(_feat)
    true
  end

  sig { params(feat: T.untyped).returns(T.nilable(String)) }
  def map_id(feat); end

  sig { params(feat: T.untyped).returns(T.nilable(String)) }
  def map_updated_at(feat); end

  sig { params(feat: T.untyped).returns(T.untyped) }
  def map_geometry(feat); end

  sig { params(feat: T.untyped).returns(T.untyped) }
  def map_tags(feat); end

  sig { params(_feat: T.untyped).returns(T.nilable(String)) }
  def map_destination_id(_feat)
    @destination_id
  end

  sig { params(_feat: T.untyped).returns(T.nilable(String)) }
  def map_source(_feat)
    @settings.attribution
  end

  def map_native_properties(_feat, _properties)
    nil
  end

  def one(row, bad)
    if !select(row)
      bad[:filtered_out] += 1
      return [nil, bad]
    end

    check = !@settings.allow_partial_source

    id = map_id(row)
    if check && id.blank?
      bad[:missing_id] += 1
      raise 'Missing id'
    end

    updated_at = map_updated_at(row)
    if check && updated_at.blank?
      bad[:missing_updated_at] += 1
      raise 'Missing updated_at'
    end

    geometry = map_geometry(row)
    if check && geometry.blank?
      bad[:missing_geometry] += 1
      raise 'Missing geometry'
    end

    geometry = map_geometry(row)
    if check && geometry[:type] == 'Point' && geometry[:coordinates] == [0.0, 0.0]
      bad[:null_island_geometry] += 1
      raise 'Null island geometry'
    end

    tags = map_tags(row)
    if check && tags.blank?
      bad[:missing_tags] += 1
      return [nil, bad]
    end

    properties = {
      destination_id: map_destination_id(row),
      type: 'Feature',
      geometry: geometry,
      properties: { tags: {} }.merge({
        id: id,
        updated_at: updated_at,
        source: map_source(row),
        tags: tags&.compact_blank,
        natives: map_native_properties(row, @settings.native_properties || {})&.compact_blank,
      }.compact_blank),
    }.compact_blank

    bad[:pass] += 1
    [properties, bad]
  rescue StandardError => e
    logger.debug(['Native', JSON.dump(row)].join("\n"))
    logger.debug(['OSM Tags', JSON.dump(properties[:properties][:tags])].join("\n")) if !properties.nil? && properties[:properties][:tags]
    logger.debug("#{e}\n\n")
    [nil, bad]
  end

  def each(raw)
    schema_data = schema
    yield [:schema, schema_data]
    osm_tags_data = osm_tags
    yield [:osm_tags, osm_tags_data]

    log = "    > #{self.class.name}, #{@destination_id.inspect}: #{raw.size}"
    log += ' +schema' if schema_data[:schema].present?
    log += ' +i18n' if schema_data[:i18n].present?
    log += ' +osm_tags' if osm_tags_data&.dig(:data).present?
    logger.info(log)
    bad = T.let({
      filtered_out: 0,
      missing_id: 0,
      missing_updated_at: 0,
      missing_geometry: 0,
      null_island_geometry: 0,
      missing_tags: 0,
      pass: 0,
    }, T.untyped)

    raw.each{ |row|
      properties, bad = one(row, bad)
      if !properties.nil?
        yield [:data, properties]
      end
    }
    bad = bad.select{ |_k, v| v != 0 }.to_h.compact_blank
    return unless !bad.empty? && bad[:pass] != raw.size

    logger.info("    ! #{bad.inspect}")
  end
end
