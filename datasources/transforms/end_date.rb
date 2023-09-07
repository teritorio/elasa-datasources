# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class EndDateTransformer < Transformer
  def initialize(settings)
    super(settings)

    @today = Time.now.strftime('%Y-%m-%d')
  end

  def process_data(row)
    end_date = row[:properties][:tags][:end_date]
    return row if !end_date || end_date >= @today

    nil
  end
end
