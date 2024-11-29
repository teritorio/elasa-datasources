# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'active_support/all'

class HashExcep < Hash
  def [](key)
    raise "Missing key \"#{key}\" in Hash at #{caller_locations[0]}" if !key?(key)

    super
  end
end

class Source
  extend T::Sig
  extend T::Helpers
  abstract!

  class MergeableInexactStruct < T::InexactStruct
    extend T::Sig

    sig { params(other: T.any(MergeableInexactStruct, T::Hash[T.untyped, T.untyped])).returns(T.self_type) }
    def deep_merge_array(other)
      if !other.is_a?(Hash)
        other = other.serialize
      end
      self.class.from_hash(serialize.deep_merge_array(other))
    end

    # What the hell we need to do this here?
    delegate :to_json, to: :serialize
  end

  class Row < MergeableInexactStruct
    const :destination_id, T.nilable(String)
  end

  class Metadata < MergeableInexactStruct
    const :name, T.nilable(T::Hash[String, String])
    const :attribution, T.nilable(String)
  end

  class MetadataRow < Row
    const :data, T::Hash[T.nilable(String), Metadata], default: {}
  end

  class SchemaRow < Row
    const :schema, T.nilable(T::Hash[String, T.untyped])
    const :i18n, T.nilable(T::Hash[String, T.untyped])
  end

  class OsmTags < MergeableInexactStruct
    const :select, T::Array[String]
    const :interest, T.nilable(T::Hash[String, nil.class])
    const :sources, T::Array[String]
  end

  class OsmTagsRow < Row
    const :data, T::Array[OsmTags], default: []
  end

  class SourceSettings < MergeableInexactStruct
    const :attribution, T.nilable(String)
    const :allow_partial_source, T::Boolean, default: false
    const :native_properties, T.nilable(T::Hash[String, T.untyped])
    const :metadata, Metadata, default: Metadata.from_hash({})
  end

  extend T::Generic
  SettingsType = type_member{ { upper: SourceSettings } } # Generic param

  sig { params(job_id: T.nilable(String), destination_id: T.nilable(String), name: T.nilable(T::Hash[String, String]), settings: SettingsType).void }
  def initialize(job_id, destination_id, name, settings)
    @job_id = job_id
    @destination_id = destination_id
    @name = name
    T.assert_type!(settings, SourceSettings) # FIXME: Manually assert type, because type is not asserted automatically, because of genereics ? (why?)
    @settings = settings
  end

  sig { returns(T::Array[MetadataRow]) }
  def metadatas
    [MetadataRow.new(
      data: {
        @destination_id => Metadata.from_hash({
          'name' => @name,
          'attribution' => @settings.attribution
        }).deep_merge_array(@settings.metadata)
      }.compact_blank
    )]
  end

  sig { returns(SchemaRow) }
  def schema
    SchemaRow.new(
      destination_id: @destination_id,
    )
  end

  sig { returns(OsmTagsRow) }
  def osm_tags
    OsmTagsRow.new(
      destination_id: @destination_id,
      data: [],
    )
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

  sig { params(_feat: T.untyped).returns(T.nilable(T::Array[T.any(Integer, String)])) }
  def map_refs(_feat); end

  def map_native_properties(_feat, _properties)
    nil
  end

  def one_error(msg, row)
    logger.debug(['Native', JSON.dump(row)].join("\n"))
    logger.debug("#{msg}\n\n")
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
      one_error('Missing id', row)
      return [nil, bad]
    end

    updated_at = map_updated_at(row)
    if check && updated_at.blank?
      bad[:missing_updated_at] += 1
      one_error('Missing updated_at', row)
      return [nil, bad]
    end

    geometry = map_geometry(row)
    if check && geometry.blank?
      bad[:missing_geometry] += 1
      one_error('Missing geometry', row)
      return [nil, bad]
    end

    geometry = map_geometry(row)
    if check && geometry[:type] == 'Point' && geometry[:coordinates] == [0.0, 0.0]
      bad[:null_island_geometry] += 1
      one_error('Null island geometry', row)
      return [nil, bad]
    end

    begin
      tags = map_tags(row)
    rescue RuntimeError => e
      one_error('Error mapping tags', row)
      logger.info(e)
      return [nil, bad]
    end

    if check && tags.blank?
      bad[:missing_tags] += 1
      return [nil, bad]
    end

    begin
      native_properties = map_native_properties(row, @settings.native_properties || {})
    rescue RuntimeError
      one_error('Error mapping native properties', row)
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
        natives: native_properties&.compact_blank,
        refs: map_refs(row)&.compact_blank,
      }.compact_blank),
    }.compact_blank

    bad[:pass] += 1
    [properties, bad]
  end

  def each(raw)
    metadata_datas = metadatas
    metadata_datas.each{ |metadata_data|
      yield [:metadata, metadata_data]
    }
    schema_data = schema
    yield [:schema, schema_data]
    osm_tags_data = osm_tags
    yield [:osm_tags, osm_tags_data]

    log = "    > #{self.class.name}, #{@destination_id.inspect}: #{raw.size}"
    log += ' +metadata' if metadata_datas.present?
    log += ' +schema' if schema_data.schema.present?
    log += ' +i18n' if schema_data.i18n.present?
    log += ' +osm_tags' if osm_tags_data.data.present?
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
