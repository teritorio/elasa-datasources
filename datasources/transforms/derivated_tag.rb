# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class DerivatedTagTransformer < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :property, String
    const :values, T::Hash[String, String]
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super
    @property = settings.property.to_sym
    @lambda_values = settings.values.transform_values{ |v| eval(v) }
  end

  def process_data(row)
    row[:properties][@property] ||= {}
    @lambda_values.each{ |key, lambda_value|
      row[:properties][@property][key] = lambda_value.call(row[:properties])
    }
    row
  end
end
