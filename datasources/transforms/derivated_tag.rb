# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class DerivatedTagTransformer < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :destination_id, T.nilable(String)
    const :replace_tags, T::Boolean, default: false
    const :replace_natives, T::Boolean, default: false
    const :exclude_tags, T.nilable(T::Array[String])
    const :exclude_natives, T.nilable(T::Array[String])
    const :tags, T.nilable(T::Hash[String, T.any(String, T::Array[String])])
    const :tags_from_natives, T.nilable(T::Hash[String, T.any(String, T::Array[String])])
    const :natives, T.nilable(T::Hash[String, T.any(String, T::Array[String])])
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super

    destination_id_lambda = @settings.destination_id
    @destination_id_lambda = eval(destination_id_lambda) if !destination_id_lambda.nil?

    @map = {
      %i[tags tags] => @settings.tags,
      %i[natives tags] => @settings.tags_from_natives,
      %i[natives natives] => @settings.natives
    }.compact.to_h{ |(property_from, property_to), prop|
      prop = prop.transform_keys(&:to_sym) if property_to == :tags
      prop = prop.transform_values{ |v|
        if v.is_a?(String) && v.start_with?('->')
          eval(v)
        elsif property_from == :tags
          if v.is_a?(String)
            v.to_sym
          else
            v.collect(&:to_sym)
          end
        else
          v
        end
      }
      [[property_from, property_to], prop]
    }
  end

  def process_data(row)
    if !@destination_id_lambda.nil?
      row[:destination_id] = @destination_id_lambda.call(row[:properties])
    end

    if @settings.replace_tags
      row[:properties][:tags] = {}
    end

    if @settings.replace_natives
      row[:properties][:natives] = {}
    end

    @map.select{ |(property_from, _property_to), _map_props|
      row[:properties][property_from].present?
    }.each{ |(property_from, property_to), map_props|
      row[:properties][property_to] ||= {}
      map_props.each{ |key, map_prop|
        row[:properties][property_to][key] = (
          if map_prop.is_a?(Proc)
            v = map_prop.call(row[:properties])
            v = v.compact_blank if v.respond_to?(:compact_blank)
            v
          elsif map_prop.is_a?(Array)
            map_prop.collect{ |k| row[:properties][property_from][k] }.compact.join(' ')
          else
            row[:properties][property_from][map_prop]
          end
        )
      }
      row[:properties][property_to] = row[:properties][property_to].compact_blank
    }

    if @settings.exclude_tags && row[:properties][:tags].present?
      row[:properties][:tags] = row[:properties][:tags].except(*@settings.exclude_tags)
    end
    if @settings.exclude_natives && row[:properties][:natives].present?
      row[:properties][:natives] = row[:properties][:natives].except(*@settings.exclude_natives)
    end

    row
  end
end
