# frozen_string_literal: true
# typed: true

require 'active_support/all'
require 'cgi'
require 'overpass_parser/visitor'

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
    if object.is_a?(Array)
      object.collect{ |o|
        deep_select(o, &block)
      }.flatten(1).compact
    elsif object.is_a?(Hash)
      deep_select(object.values, &block) + (block.call(object) ? [object] : [])
    end
  end

  sig { returns(OsmTagsRow) }
  def osm_tags
    if @selectors.blank?
      tree = OverpassParser.tree(@settings.query)
      tags_all = {}
      selects = deep_select(tree) { |o| o[:type] == :query_object }.select{ |query_object|
        query_object[:selectors].present?
      }.collect{ |query_object|
        tags = query_object[:selectors].collect{ |selector|
          key, value = (
            if selector[:operator].nil?
              next if selector[:not]

              [selector[:key], nil]
            elsif selector[:operator][0] == '='
              [selector[:key], [selector[:value]]]
            else
              [selector[:key], nil]
            end
          )

          if !tags_all.key?(key)
            tags_all[key] = value
          elsif value.nil?
            tags_all[key] = nil
          elsif !tags_all[key].nil?
            tags_all[key] += value
          end

          [key, value]
        }.compact.to_h

        tags.collect{ |k, v|
          s = "[#{quote(k)}"
          if !v.nil?
            s += v.size == 1 ? '=' : '~'
            s += v.collect{ |w| quote(w) }.join('|')
          end
          s + ']'
        }.join
      }

      super().deep_merge_array({
        'data' => selects.collect{ |select|
          {
            'select' => [select],
            'interest' => tags_all.merge(@settings.interest&.to_h{ |key| [key, nil] } || {}),
            'sources' => [@job_id, @destination_id].uniq
          }
        }
      })
    else
      super().deep_merge_array({
        'data' => @selectors.collect{ |selector|
          {
            'select' => selector.is_a?(Array) ? selector : [selector],
            'interest' => @settings.interest&.to_h{ |key| [key, nil] },
            'sources' => [@job_id, @destination_id].uniq
          }
        }
      })
    end
  end

  private

  def quote(string)
    simple_quote = string.include?("'")
    double_quote = string.include?('"')
    if simple_quote || double_quote || /[^-_a-zA-Z0-9]/.match?(string)
      if double_quote && !simple_quote
        "'#{string}'"
      else
        "\"#{string.gsub('\"', '\\\"')}\""
      end
    else
      string
    end
  end
end
