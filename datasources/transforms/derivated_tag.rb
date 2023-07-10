# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class DerivatedTagTransformer < Transformer
  def initialize(settings)
    super(settings)
    @key = settings['key'].to_sym
    @lambda_value = eval(settings['value'])
  end

  def process_data(row)
    row[:properties][:tags][@key] = @lambda_value.call(row[:properties])
    row
  end
end
