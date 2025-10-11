# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class FilterByValuesTransformer < Transformer
  extend T::Generic

  class Settings < Transformer::TransformerSettings
    const :tags, T.nilable(T::Hash[String, T::Array[String]])
    const :natives, T.nilable(T::Hash[String, T::Array[String]])
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super
    @tags_sym = @settings.tags&.transform_keys(&:to_sym) if !@settings.tags.nil?
  end

  def process_data(row)
    return if !@tags_sym.nil? && !@tags_sym.all?{ |key, values|
      values.include?(row[:properties][:tags][key])
    }

    return if !@settings.natives.nil? && !@settings.natives&.all?{ |key, values|
      values.include?(row[:properties][:natives][key])
    }

    row
  end
end
