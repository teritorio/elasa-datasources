# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class DerivatedTagTransformer < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :replace_tags, T::Boolean, default: false
    const :replace_natives, T::Boolean, default: false
    const :tags, T.nilable(T::Hash[String, T.any(String, T::Array[String])])
    const :natives, T.nilable(T::Hash[String, T.any(String, T::Array[String])])
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super
    @map_tags, @map_natives = [@settings.tags, @settings.natives].collect{ |prop|
      prop&.transform_values{ |v|
        if v.is_a?(String) && v.start_with?('->')
          eval(v)
        elsif v.is_a?(String)
          v.to_sym
        else
          v.collect(&:to_sym)
        end
      }
    }
  end

  def process_data(row)
    if @settings.replace_tags
      row[:properties][:tags] = {}
    end

    if @settings.replace_natives
      row[:properties][:natives] = {}
    end

    { tags: @map_tags, natives: @mpa_natives }.select{ |property, map_props|
      !map_props.nil? && row[:properties][property].present?
    }.each{ |property, map_props|
      map_props.each{ |key, map_prop|
        row[:properties][property][key] = (
          if map_prop.is_a?(Proc)
            map_prop.call(row[:properties]).compact_blank
          elsif map_prop.is_a?(Array)
            map_prop.collect{ |k| row[:properties][property][k] }.compact.join(' ')
          else
            row[:properties][property][map_prop]
          end
        )
      }
      row[:properties][property] = row[:properties][property].compact_blank
    }
    row
  end
end
