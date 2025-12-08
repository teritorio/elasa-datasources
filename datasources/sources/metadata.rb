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

  sig { returns(SchemaRow) }
  def schema
    super.deep_merge_array({
      'tags_schema' => load(@settings.tags_schema_file)&.inject({}, &:deep_merge_array),
      'natives_schema' => load(@settings.natives_schema_file)&.compact&.inject({}, &:deep_merge_array),
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
