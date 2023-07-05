# frozen_string_literal: true
# typed: true

class DerivatedTagTransformer
  def initialize(settings)
    @key = settings['key'].to_sym
    @lambda_value = eval(settings['value'])
  end

  def process(row)
    row[:properties][:tags][@key] = @lambda_value.call(row[:properties])
    row
  end
end
