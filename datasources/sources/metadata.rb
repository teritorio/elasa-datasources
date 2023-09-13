# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class MetadataSource < Source
  extend T::Sig

  class Settings < Source::SourceSettings
    const :meta, T.nilable(T::Array[String])
    const :schema, T.nilable(T::Array[String])
    const :i18n, T.nilable(T::Array[String])
    const :osm_tags, T.nilable(String)
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def load(urls)
    urls&.collect{ |url|
      JSON.parse(File.read(url))
    }
  end

  def metadata
    super.deep_merge_array({
      data: load(@settings.meta)&.inject({}, &:deep_merge_array),
    })
  end

  def schema
    super.deep_merge_array({
      schema: load(@settings.schema)&.inject({}, &:deep_merge_array),
      i18n: load(@settings.i18n)&.inject({}, &:deep_merge_array),
    })
  end

  def osm_tags
    super.deep_merge_array({
      data: load(@settings.osm_tags)&.inject([], &:+),
    })
  end

  def each
    super([])
  end
end
