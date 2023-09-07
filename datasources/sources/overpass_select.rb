# frozen_string_literal: true
# typed: true

require 'active_support/all'
require 'cgi'

require 'sorbet-runtime'

require_relative 'overpass'


class OverpassSelectSource < OverpassSource
  extend T::Sig

  class Settings < OverpassSource::Settings
    const :query, T.nilable(String), override: true
    const :select, T.nilable(T.any(String, T::Hash[String, T.untyped]))
    const :relation_id, T.nilable(Integer)
    const :interest, T.nilable(T::Array[String])
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(job_id: T.nilable(String), destination_id: T.nilable(String), settings: Settings).void }
  def initialize(job_id, destination_id, settings)
    query = (
      if settings.query
        settings.query
      else
        @selectors = (
          if settings.select.is_a?(String)
            settings.select
          else
            T.cast(settings.select, Hash).collect{ |k, v| v.nil? ? "[#{k}]" : "[#{k}=#{v}]" }.join
          end
        )
        area_id = 3_600_000_000 + T.must(settings.relation_id)
        "
[out:json][timeout:25];
area(#{area_id})->.a;
nwr#{@selectors}(area.a);
out center meta;
"
      end
    )

    super(job_id, destination_id, settings.with(query: query))
  end

  def osm_tags
    return if !@settings.select || @settings.select.is_a?(String)

    super().merge({
      data: [{
        select: @selectors,
        interest: @settings.interest&.to_h{ |key| [key, nil] },
        sources: [@job_id, @destination_id].uniq
      }]
    })
  end
end
