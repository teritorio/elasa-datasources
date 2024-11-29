# frozen_string_literal: true
# typed: false

require_relative 'transformer'


class EndDateTransformer < Transformer
  extend T::Generic
  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super

    @today = Time.current.strftime('%Y-%m-%d')
  end

  def process_data(row)
    end_date = row[:properties][:tags][:end_date]
    return row if !end_date || end_date >= @today

    nil
  end
end
