# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class MockSource < Source
  extend T::Sig

  class Settings < Source::SourceSettings
    const :schema, T.nilable(String)
    const :i18n, T.nilable(String)
    const :osm_tags, T.nilable(String)
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  def schema
    super.merge({
      schema: @settings.schema,
      i18n: @settings.i18n,
  }.compact)
  end

  def osm_tags
    if @settings.osm_tags
      super.merge({ data: @settings.osm_tags })
    else
      super
    end
  end

  def each
    super([])
  end
end
