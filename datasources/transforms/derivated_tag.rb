# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class DerivatedTagTransformer < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :key, String
    const :value, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: Settings).void }
  def initialize(settings)
    super(settings)
    @key = settings.key.to_sym
    @lambda_value = eval(settings.value)
  end

  def process_data(row)
    row[:properties][:tags][@key] = @lambda_value.call(row[:properties])
    row
  end
end
