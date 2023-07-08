# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class ValidateTransformer < Transformer
  def initialize(settings)
    super(settings)

    @count = 0
    @bad = {
      missing_id: 0,
      missing_updated_at: 0,
      missing_geometry: 0,
      null_island_geometry: 0,
      missing_tags: 0,
      pass: 0,
    }
  end

  def process(row)
    @count += 1

    if row[:properties][:id].blank?
      @bad[:missing_id] += 1
      return
    end

    if row[:properties][:updated_at].blank?
      @bad[:missing_updated_at] += 1
      return
    end

    if row[:geometry].blank?
      @bad[:missing_geometry] += 1
      return
    end

    if row[:geometry][:type] == 'Point' && row[:geometry][:coordinates] == [0.0, 0.0]
      @bad[:null_island_geometry] += 1
      return
    end

    @bad[:pass] += 1
    row
  end

  def close
    bad = @bad.select{ |_k, v| v != 0 }.to_h.compact_blank
    return unless !bad.empty? && bad[:pass] != @count

    puts bad.inspect
  end
end
