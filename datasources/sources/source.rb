# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'active_support/all'
require_relative '../json_schema'

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

  class ReportIssue < MergeableInexactStruct
    const :url_template, String
    const :value_extractors, T.nilable(T::Hash[String, String])
  end

  class Row < MergeableInexactStruct
    const :destination_id, T.nilable(String)
  end

  class Metadata < MergeableInexactStruct
    const :name, T.nilable(T::Hash[String, String])
    const :attribution, T.nilable(String)
    const :report_issue, T.nilable(ReportIssue)
  end

  class MetadataRow < Row
    const :destination_internal, T.nilable(T::Boolean)
    const :data, T::Hash[T.nilable(String), Metadata], default: {}
  end

  class SchemaRow < Row
    const :tags_schema, T.nilable(JsonSchema)
    const :natives_schema, T.nilable(JsonSchema)
    const :i18n, T.nilable(T::Hash[String, T.untyped])

    def deep_merge_array(other)
      self.class.from_hash({
        'destination_id' => destination_id,
        'tags_schema' => (tags_schema || JsonSchema.new).deep_merge_array(other.tags_schema || JsonSchema.new),
        'natives_schema' => (natives_schema || JsonSchema.new).deep_merge_array(other.natives_schema || JsonSchema.new),
        'i18n' => (i18n || {}).deep_merge_array(other.i18n || {}),
      })
    end
  end

  class OsmTags < MergeableInexactStruct
    const :select, T.nilable(T::Array[String])
    const :interest, T.nilable(T::Hash[String, nil.class])
    const :sources, T::Array[String]
  end

  class OsmTagsRow < Row
    const :data, T::Array[OsmTags], default: []
  end

  class SourceSettings < MergeableInexactStruct
    const :destination_id, T.nilable(String)
    const :destination_internal, T.nilable(T::Boolean)
    const :attribution, T.nilable(String)
    const :report_issue, T.nilable(ReportIssue)
    const :allow_partial_source, T::Boolean, default: false
    const :native_properties, T.nilable(T::Hash[String, T.untyped])
    const :tags_schema, T.nilable(T::Hash[String, T.untyped])
    const :natives_schema, T.nilable(T::Hash[String, T.untyped])
    const :i18n, T.nilable(T::Hash[String, T.untyped])
    const :exclusion_filter, T.nilable(String)
    const :metadata, Metadata, default: Metadata.from_hash({})

    @exclusion_filter_proc = T.let(nil, T.nilable(T.proc.params(_: T.untyped).returns(T::Boolean)))

    def exclusion_filter_call(row)
      return if exclusion_filter.nil?

      if @exclusion_filter_proc.nil?
        @exclusion_filter_proc = eval(T.must(exclusion_filter))
      end

      @exclusion_filter_proc.call(row)
    end
  end

  extend T::Generic

  SettingsType = type_member{ { upper: SourceSettings } } # Generic param

  sig { params(job_id: T.nilable(String), destination_id: T.nilable(String), name: T.nilable(T::Hash[String, String]), settings: SettingsType).void }
  def initialize(job_id, destination_id, name, settings)
    @job_id = job_id
    @destination_id = settings.destination_id || destination_id
    @name = name
    T.assert_type!(settings, SourceSettings) # FIXME: Manually assert type, because type is not asserted automatically, because of genereics ? (why?)
    @settings = settings
  end

  sig { returns(T::Array[MetadataRow]) }
  def metadatas
    [MetadataRow.new(
      destination_internal: @settings.destination_internal,
      data: {
        @destination_id => Metadata.from_hash({
          'name' => @name,
          'attribution' => @settings.attribution,
          'report_issue' => @settings.report_issue&.serialize,
        }).deep_merge_array(@settings.metadata)
      }.compact_blank
    )]
  end

  sig { returns(SchemaRow) }
  def schema
    SchemaRow.new(
      destination_id: @destination_id,
      tags_schema: (JsonSchema.new(T.must(@settings.tags_schema)) if !@settings.tags_schema.nil?),
      natives_schema: (JsonSchema.new(T.must(@settings.natives_schema)) if !@settings.natives_schema.nil?),
      i18n: @settings.i18n,
    )
  end

  sig { returns(OsmTagsRow) }
  def osm_tags
    OsmTagsRow.new(
      destination_id: @destination_id,
      data: [],
    )
  end

  def select?(_feat)
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
    if !@settings.exclusion_filter.nil? && @settings.exclusion_filter_call(row)
      bad[:exclusion_filter] += 1
      return [nil, bad]
    end

    if !select?(row)
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

    begin
      native_properties = map_native_properties(row, @settings.native_properties || {})
    rescue RuntimeError
      one_error('Error mapping native properties', row)
      return [nil, bad]
    end

    if check && tags.blank? && native_properties.blank?
      bad[:missing_tags_natives] += 1
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

  sig {
    params(
      block: T.proc.params(_: [Symbol, T.untyped]).void,
    ).void
  }
  def each(&block); end

  sig {
    params(
      raw: T::Enumerable[T::Hash[String, String]],
      _block: T.proc.params(_: [Symbol, T.untyped]).void,
    ).void
  }
  def loop(raw, &_block)
    metadata_datas = metadatas
    metadata_datas.each{ |metadata_data|
      yield [:metadata, metadata_data]
    }
    schema_data = schema
    yield [:schema, schema_data]
    osm_tags_data = osm_tags
    yield [:osm_tags, osm_tags_data]

    bad = T.let({
      exclusion_filter: 0,
      filtered_out: 0,
      missing_id: 0,
      missing_updated_at: 0,
      missing_geometry: 0,
      null_island_geometry: 0,
      missing_tags_natives: 0,
      pass: 0,
    }, T.untyped)

    raw_count = 0
    raw.each{ |row|
      raw_count += 1
      properties, bad = one(row, bad)
      if !properties.nil?
        yield [:data, properties]
      end
    }

    log = "    > #{self.class.name}, #{@destination_id.inspect}: #{raw_count}"
    log += ' +metadata' if metadata_datas.present?
    log += ' +tags_schema' if schema_data.tags_schema.present?
    log += ' +natives_schema' if schema_data.natives_schema.present?
    log += ' +i18n' if schema_data.i18n.present?
    log += ' +osm_tags' if osm_tags_data.data.present?
    logger.info(log)

    bad = bad.select{ |_k, v| v != 0 }.to_h.compact_blank
    return unless !bad.empty? && bad[:pass] != raw_count

    logger.info("    ! #{bad.inspect}")
  end
end
