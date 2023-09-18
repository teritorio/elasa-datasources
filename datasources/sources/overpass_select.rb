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
    const :select, T.nilable(T.any(String, T.any(T::Hash[String, T.any(String, T::Boolean)], T::Array[T::Hash[String, T.any(String, T::Boolean)]])))
    const :relation_id, T.nilable(Integer)
    const :interest, T.nilable(T::Array[String])
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(job_id: T.nilable(String), destination_id: T.nilable(String), name: T.nilable(T::Hash[String, String]), settings: SettingsType).void }
  def initialize(job_id, destination_id, name, settings)
    query = (
      if settings.query
        settings.query
      else
        @selectors = []
        query_selectors = (
          if settings.select.is_a?(String)
            settings.select
          else
            select = settings.select
            if select.is_a?(Hash)
              select = [settings.select]
            end
            T.cast(select, T::Array[T::Hash[String, T.untyped]]).collect{ |select_hash|
              selector = select_hash.collect{ |k, v|
                if v.nil?
                  "[#{k}]"
                else
                  v = v == true ? 'yes' : v == false ? 'no' : v
                  "[\"#{k}\"=\"#{v}\"]"
                end
              }.join
              @selectors << selector
              "nwr#{selector}(area.a);"
            }.join("\n")
          end
        )
        area_id = 3_600_000_000 + T.must(settings.relation_id)
        "
[out:json][timeout:25];
area(#{area_id})->.a;
(
#{query_selectors}
);
out center meta;
"
      end
    )

    super(job_id, destination_id, name, settings.with(query: query))
  end

  def osm_tags
    return if !@settings.select || @settings.select.is_a?(String)

    super().merge({
      data: @selectors.collect{ |selector|
        {
          select: selector,
          interest: @settings.interest&.to_h{ |key| [key, nil] },
          sources: [@job_id, @destination_id].uniq
        }
      }
    })
  end
end
