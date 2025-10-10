# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class LogTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  def process_data(row)
    puts row.inspect
    row
  end
end
