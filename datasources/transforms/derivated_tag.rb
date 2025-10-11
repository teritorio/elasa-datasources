# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class DerivatedTagTransformer < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :tags, T.nilable(T::Hash[String, String])
    const :natives, T.nilable(T::Hash[String, String])
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super
    @lambda_tags, @lambda_natives = [@settings.tags, @settings.natives].collect{ |prop|
      prop&.transform_values{ |v| eval(v) }
    }
  end

  def process_data(row)
    { tags: @lambda_tags, natives: @lambda_natives }.select{ |property, lambda_props|
      !lambda_props.nil? && row[:properties][property].present?
    }.each{ |property, lambda_props|
      lambda_props.each{ |key, lambda_prop|
        row[:properties][property][key] = lambda_prop.call(row[:properties])
      }
    }
    row
  end
end
