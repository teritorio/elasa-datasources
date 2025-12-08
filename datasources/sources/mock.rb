# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class MockSource < Source
  extend T::Sig

  class Settings < Source::SourceSettings
    const :tags_schema, T.nilable(T::Hash[String, T.untyped])
    const :i18n, T.nilable(T::Hash[String, T.untyped])
    const :osm_tags, T.nilable(T::Array[Source::OsmTags])
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { returns(SchemaRow) }
  def schema
    super.deep_merge_array({
      'tags_schema' => @settings.tags_schema,
      'i18n' => @settings.i18n,
  }.compact)
  end

  sig { returns(OsmTagsRow) }
  def osm_tags
    if @settings.osm_tags
      super.deep_merge_array(OsmTagsRow.new(data: @settings.osm_tags))
    else
      super
    end
  end

  def each(&block)
    loop([], &block)
  end
end
