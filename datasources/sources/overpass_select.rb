# frozen_string_literal: true
# typed: true

require 'active_support/all'
require 'cgi'
require 'overpass_parser'
require 'overpass_parser/nodes/query_objects'
require 'overpass_parser/nodes/selectors'

require 'sorbet-runtime'

require_relative 'overpass'


class OverpassSelectSource < OverpassSource
  extend T::Sig

  class Settings < OverpassSource::Settings
    const :query, T.nilable(String), override: true
    const :select, T.nilable(T.any(
      String,
      T::Hash[String, T.any(String, T::Boolean)],
      T::Array[T::Hash[String, T.any(String, T::Boolean)]],
    ))
    const :relation_ids, T.nilable(T::Array[Integer])
    const :interest, T.nilable(T::Array[String])
    const :with_osm_tags, T::Boolean, default: true
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
          selects = settings.select
          if !selects.is_a?(Array)
            selects = [settings.select]
          end
          selects.collect{ |select|
            if select.is_a?(String)
              "nwr#{select}(area.a);"
            else
              selector = T.cast(select, T::Hash[String, T.untyped]).collect{ |k, v|
                if v.nil?
                  "[#{k}]"
                else
                  v = v == true ? 'yes' : v == false ? 'no' : v
                  "[\"#{k}\"=\"#{v}\"]"
                end
              }.join
              @selectors << selector
              "nwr#{selector}(area.a);"
            end
          }.join("\n")
        )
        area_ids = T.must(settings.relation_ids).collect{ |id| 3_600_000_000 + id }.collect(&:to_s).join(',')
        "
[out:json][timeout:25];
area(id:#{area_ids})->.a;
(
#{query_selectors}
);
out center meta;
"
      end
    )

    super(job_id, destination_id, name, settings.with(query: query))
  end

  def deep_select(object, &block)
    if object.is_a?(OverpassParser::Nodes::QueryObjects)
      object.selectors&.to_overpass
    elsif object.is_a?(OverpassParser::Nodes::Request) || object.is_a?(OverpassParser::Nodes::QueryUnion)
      object.queries.collect{ |o|
        deep_select(o, &block)
      }.flatten(1).compact
    end
  end

  sig { returns(OsmTagsRow) }
  def osm_tags
    return super if !@settings.with_osm_tags

    if !@settings.query.nil?
      tree = OverpassParser.parse(T.must(@settings.query))
      selects = deep_select(tree)

      super.deep_merge_array({
        'data' => selects.collect{ |select|
          {
            'select' => [select],
            'interest' => (@settings.interest&.to_h{ |key| [key, nil] }) || {},
            'sources' => [@job_id, @destination_id].uniq
          }
        }
      })
    elsif @selectors.present?
      super.deep_merge_array({
        'data' => @selectors.collect{ |selector|
          {
            'select' => selector.is_a?(Array) ? selector : [selector],
            'interest' => @settings.interest&.to_h{ |key| [key, nil] },
            'sources' => [@job_id, @destination_id].uniq
          }
        }
      })
    else
      raise 'Configuration error'
    end
  end
end
