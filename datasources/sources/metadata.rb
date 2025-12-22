# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class MetadataSource < Source
  extend T::Sig

  class Settings < Source::SourceSettings
    const :meta, T.nilable(T::Array[String])
    const :tags_schema_file, T.nilable(T::Array[String])
    const :natives_schema_file, T.nilable(T::Array[String])
    const :i18n_file, T.nilable(T::Array[String])
    const :osm_tags, T.nilable(T::Array[String])
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig{ params(urls: T.nilable(T::Array[String])).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
  def load(urls)
    urls&.collect{ |url|
      JSON.parse(File.read(url))
    }
  end

  sig { returns(T::Array[MetadataRow]) }
  def metadatas
    [T.must(super[0]).deep_merge_array({
      'data' => load(@settings.meta)&.inject({}, &:deep_merge_array),
    })]
  end

  sig { params(schemas: T::Array[T::Hash[String, T.untyped]]).returns(T::Hash[String, T.untyped]) }
  def schema_merge(schemas)
    {
      'required' => schemas.collect{ |s| s['required'] || [] }.inject([], &:intersection).compact_blank,
      'additionalProperties' => schemas.collect{ |s| s['additionalProperties'] || true }.any?,
      'properties' => schemas.collect{ |s| s['properties'] }.compact.inject({}, &:deep_merge_array).compact_blank,
      '$defs' => schemas.collect{ |s| s['$defs'] }.compact.inject({}, &:deep_merge_array).compact_blank,
    }.compact
  end

  sig { returns(SchemaRow) }
  def schema
    super.deep_merge_array({
      'tags_schema' => schema_merge(load(@settings.tags_schema_file)&.compact || []),
      'natives_schema' => schema_merge(load(@settings.natives_schema_file)&.compact || []),
      'i18n' => load(@settings.i18n_file)&.inject({}, &:deep_merge_array),
    })
  end

  sig { returns(OsmTagsRow) }
  def osm_tags
    super.deep_merge_array({
      'data' => load(@settings.osm_tags)&.inject([], &:+),
    })
  end

  def each(&block)
    loop([], &block)
  end
end
